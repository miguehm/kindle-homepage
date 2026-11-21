# Security Policy

## Supported versions

Security fixes are applied to the latest released version. Older releases are
not maintained; please upgrade before reporting an issue.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please **do not** open a public issue for a security problem. Use GitHub's
private vulnerability reporting on this repository (**Security → Report a
vulnerability**), or contact the maintainer privately through GitHub.

Include:

- affected version and platform,
- steps to reproduce,
- impact and any suggested fix,
- whether you have already disclosed it elsewhere.

You should receive an acknowledgement, and an update once the issue is triaged.
Please allow time for a fix before any public disclosure.

## Notes for users

- `hnmd_api_key` is a local plaintext setting stored by KOReader. It is masked
  in the UI and never written to logs, but anyone with access to your device's
  settings files can read it. Protect physical/local access to the device.
- Article bodies are rendered to an ephemeral HTML file under the KOReader data
  cache and removed when the reader closes. Markdown links from untrusted
  articles are sanitized; unsafe URLs are rendered as plain text and images
  are never fetched implicitly.
- Run releases from the official Releases page and verify the plugin folder is
  named exactly `kindlehome.koplugin` before loading it in KOReader.
