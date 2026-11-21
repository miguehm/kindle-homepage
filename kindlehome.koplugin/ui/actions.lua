-- SPDX-License-Identifier: MIT
local Logger = require("lib/logger")

local Actions = {}
Actions.__index = Actions

function Actions:new(opts)
    opts = opts or {}
    return setmetatable({
        handlers = {},
        config = opts.config,
    }, self)
end

function Actions:register(id_prefix, handler)
    self.handlers[id_prefix] = handler
end

function Actions:dispatch(action_id, ctx)
    if type(action_id) ~= "string" or action_id == "" then
        return false, "invalid_action"
    end
    ctx = ctx or {}
    Logger.info("actions", "dispatch", { action = action_id })

    local exact = self.handlers[action_id]
    if type(exact) == "function" then
        return true, exact(ctx, action_id)
    end

    local prefix, arg = action_id:match("^([^:]+):(.*)$")
    if prefix and self.handlers[prefix] then
        ctx.action_arg = arg
        ctx.action_prefix = prefix
        return true, self.handlers[prefix](ctx, action_id, arg)
    end

    local prefix2 = action_id:match("^([^:]+)$")
    if prefix2 and self.handlers[prefix2] then
        return true, self.handlers[prefix2](ctx, action_id, nil)
    end

    Logger.warn("actions", "unhandled", { action = action_id })
    return false, "unhandled"
end

return Actions
