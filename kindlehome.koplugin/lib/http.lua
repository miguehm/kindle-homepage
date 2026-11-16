local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local rapidjson = require("rapidjson")

local Logger = require("lib/logger")

local Http = {}

local USER_AGENT = "KindleHome/0.1 (KOReader; Kindle)"

local function now_ms()
    local ok, t = pcall(socket.gettime)
    if ok and type(t) == "number" then return t end
    return os.time()
end

local function classify_socket_err(err)
    err = tostring(err or "")
    local e = err:lower()
    if e:find("timeout", 1, true) then return "timeout" end
    if e:find("wantread", 1, true) or e:find("wantwrite", 1, true) then return "timeout" end
    if e:find("closed", 1, true) or e:find("reset", 1, true) or e:find("refused", 1, true)
        or e:find("host", 1, true) or e:find("resolve", 1, true) or e:find("unreachable", 1, true) then
        return "network"
    end
    return "network"
end

local function is_transient(kind)
    return kind == "timeout" or kind == "network"
end

local function result_error(kind, detail, status, headers)
    return { ok = false, error_kind = kind, error = detail, status = status, headers = headers }
end

local function read_limited_body(response, max_bytes)
    if type(response) == "string" then
        if #response > max_bytes then
            return nil, "too_large"
        end
        return response, nil
    end
    if type(response) == "table" then
        local body = table.concat(response)
        if #body > max_bytes then
            return nil, "too_large"
        end
        return body, nil
    end
    return "", nil
end

local function do_get(url, opts)
    opts = opts or {}
    local timeout = tonumber(opts.timeout_s) or 10
    local max_bytes = tonumber(opts.max_bytes) or 524288
    local headers = {
        ["user-agent"] = opts.user_agent or USER_AGENT,
        ["accept"] = opts.accept or "*/*",
    }
    if opts.bearer_token and opts.bearer_token ~= "" then
        headers["authorization"] = "Bearer " .. opts.bearer_token
    end
    if type(opts.headers) == "table" then
        for k, v in pairs(opts.headers) do headers[k] = v end
    end

    local sink_tbl = {}
    local sink = ltn12.sink.table(sink_tbl)
    local bytes = 0
    local too_large = false
    local limited_sink = function(chunk, err)
        if chunk == nil then return sink(chunk, err) end
        if err then return nil, err end
        bytes = bytes + #chunk
        if bytes > max_bytes then
            too_large = true
            return nil, "too_large"
        end
        return sink(chunk)
    end

    local req = {
        url = url,
        method = "GET",
        headers = headers,
        sink = limited_sink,
        redirect = opts.redirect ~= false,
    }

    socketutil:set_timeout(timeout, timeout)

    local ok_call, r1, r2, r3, r4 = pcall(http.request, req)
    socketutil:reset_timeout()

    if not ok_call then
        return result_error(classify_socket_err(r1), tostring(r1))
    end

    -- LuaSocket http.request returns: body_or_1, code, headers, status_line (varies by form)
    local code = tonumber(r2) or tonumber(r1)
    local resp_headers = type(r3) == "table" and r3 or nil
    local status_line = r4 or r3

    if too_large then
        return result_error("too_large", "response exceeded max_bytes", code, resp_headers)
    end

    local body, body_err = read_limited_body(sink_tbl, max_bytes)
    if not body then
        return result_error(body_err or "too_large", "response exceeded max_bytes", code, resp_headers)
    end

    -- On failure some forms return nil, code(err), nil, ...
    if r1 == nil and type(r2) == "string" and code == nil then
        local kind = classify_socket_err(r2)
        return result_error(kind, r2)
    end

    if type(code) ~= "number" then
        return result_error("network", "no_status:" .. tostring(r2), nil, resp_headers)
    end

    if code == 401 then
        return { ok = false, status = 401, headers = resp_headers, body = body, error_kind = "http_401", error = status_line }
    elseif code == 404 then
        return { ok = false, status = 404, headers = resp_headers, body = body, error_kind = "http_404", error = status_line }
    elseif code == 503 then
        return { ok = false, status = 503, headers = resp_headers, body = body, error_kind = "http_503", error = status_line }
    elseif code < 200 or code >= 300 then
        return { ok = false, status = code, headers = resp_headers, body = body, error_kind = "http_other", error = status_line }
    end

    return { ok = true, status = code, headers = resp_headers, body = body }
end

function Http.get(url, opts)
    opts = opts or {}
    local start = now_ms()
    Logger.info("http", "fetch_start", { url = url })
    local res = do_get(url, opts)
    local retries = tonumber(opts.retries) or 0
    if not res.ok and res.error_kind ~= "http_401" and is_transient(res.error_kind) and retries > 0 then
        for i = 1, retries do
            Logger.warn("http", "retry", { url = url, attempt = i, kind = res.error_kind })
            res = do_get(url, opts)
            if res.ok or res.error_kind == "http_401" or not is_transient(res.error_kind) then
                break
            end
        end
    end
    res.elapsed_ms = math.floor((now_ms() - start) * 1000)
    if res.ok then
        Logger.info("http", "fetch_ok", { url = url, status = res.status, ms = res.elapsed_ms })
    else
        Logger.warn("http", "fetch_error", { url = url, status = res.status, kind = res.error_kind })
    end
    return res
end

-- Streaming GET to a file. The body is never accumulated in RAM (Kindle PW5
-- has ~15 MB free), max_bytes is enforced while receiving, Content-Length is
-- validated, and the destination is removed on any failure. Callers pass a
-- temporary path and promote it with rename once ok.
local function do_get_to_file(url, opts)
    local path = opts and opts.path
    if type(path) ~= "string" or path == "" then
        return result_error("network", "missing_path")
    end
    local timeout = tonumber(opts.timeout_s) or 10
    local max_bytes = tonumber(opts.max_bytes) or 524288
    local headers = {
        ["user-agent"] = opts.user_agent or USER_AGENT,
        ["accept"] = opts.accept or "*/*",
    }
    if opts.bearer_token and opts.bearer_token ~= "" then
        headers["authorization"] = "Bearer " .. opts.bearer_token
    end
    if type(opts.headers) == "table" then
        for k, v in pairs(opts.headers) do headers[k] = v end
    end

    local file, open_err = io.open(path, "wb")
    if not file then
        return result_error("network", "open_failed:" .. tostring(open_err))
    end

    local bytes = 0
    local too_large = false
    local write_error = nil
    local function close_file()
        if file then
            file:close()
            file = nil
        end
    end
    local sink = function(chunk, err)
        if err then
            write_error = tostring(err)
            return nil, err
        end
        if chunk == nil then
            close_file()
            return 1
        end
        bytes = bytes + #chunk
        if bytes > max_bytes then
            too_large = true
            return nil, "too_large"
        end
        local ok_w, werr = file:write(chunk)
        if not ok_w then
            write_error = tostring(werr)
            return nil, "write_failed"
        end
        return 1
    end

    local req = {
        url = url,
        method = "GET",
        headers = headers,
        sink = sink,
        redirect = opts.redirect ~= false,
    }

    socketutil:set_timeout(timeout, timeout)
    local ok_call, r1, r2, r3, r4 = pcall(http.request, req)
    socketutil:reset_timeout()
    close_file()

    local function fail(kind, detail, status, resp_headers)
        pcall(os.remove, path)
        return result_error(kind, detail, status, resp_headers)
    end

    if not ok_call then
        return fail(classify_socket_err(r1), tostring(r1))
    end
    if too_large then
        return fail("too_large", "response exceeded max_bytes")
    end
    if write_error then
        return fail("network", "write_failed:" .. write_error)
    end

    local code = tonumber(r2) or tonumber(r1)
    local resp_headers = type(r3) == "table" and r3 or nil
    local status_line = r4 or r3

    if r1 == nil and type(r2) == "string" and code == nil then
        return fail(classify_socket_err(r2), r2)
    end
    if type(code) ~= "number" then
        return fail("network", "no_status:" .. tostring(r2), nil, resp_headers)
    end

    if code < 200 or code >= 300 then
        if code == 401 then
            return fail("http_401", status_line, code, resp_headers)
        elseif code == 404 then
            return fail("http_404", status_line, code, resp_headers)
        elseif code == 503 then
            return fail("http_503", status_line, code, resp_headers)
        end
        return fail("http_other", status_line, code, resp_headers)
    end

    local declared = resp_headers and resp_headers["content-length"]
    local declared_n = tonumber(declared)
    if declared_n and declared_n ~= bytes then
        return fail("incomplete", "content_length_mismatch", code, resp_headers)
    end

    return { ok = true, status = code, headers = resp_headers, bytes = bytes }
end

function Http.get_to_file(url, opts)
    opts = opts or {}
    local start = now_ms()
    Logger.info("http", "fetch_file_start", { url = url })
    local res = do_get_to_file(url, opts)
    local retries = tonumber(opts.retries) or 0
    if not res.ok and is_transient(res.error_kind) and retries > 0 then
        for i = 1, retries do
            Logger.warn("http", "retry_file", { url = url, attempt = i, kind = res.error_kind })
            res = do_get_to_file(url, opts)
            if res.ok or not is_transient(res.error_kind) then
                break
            end
        end
    end
    res.elapsed_ms = math.floor((now_ms() - start) * 1000)
    if res.ok then
        Logger.info("http", "fetch_file_ok", {
            url = url, status = res.status, bytes = res.bytes, ms = res.elapsed_ms,
        })
    else
        Logger.warn("http", "fetch_file_error", {
            url = url, status = res.status, kind = res.error_kind,
        })
    end
    return res
end

function Http.get_json(url, opts)
    local res = Http.get(url, opts)
    if not res.ok then
        return res
    end
    local ok_decode, decoded = pcall(rapidjson.decode, res.body or "")
    if not ok_decode then
        return result_error("parse", "invalid_json", res.status, res.headers)
    end
    res.json = decoded
    return res
end

return Http
