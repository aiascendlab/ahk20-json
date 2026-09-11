<div align="center">

# AHK20_JSON

**Strict [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html) JSON parser and serializer for [AutoHotkey v2](https://www.autohotkey.com/).**

[Documentation](docs/getting-started.md) · [Examples](examples/basic.ahk) · [Report a Bug](https://github.com/aiascendlab/ahk20-json/issues/new/choose) · [Security](SECURITY.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2-green.svg)](https://www.autohotkey.com/) [![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D4.svg)](docs/getting-started.md#requirements) [![Status: Active](https://img.shields.io/badge/Status-Active-success.svg)](#project-status)

</div>

## Why

AutoHotkey does not natively support JSON. Existing open-source JSON parsers may accept incomplete objects, invalid numbers, or a trailing NUL after a value, which poses risks for production scripts.

AHK20_JSON is a strict RFC 8259 implementation that passes all 318 tests from [nst/JSONTestSuite](https://github.com/nst/JSONTestSuite).

## Features

- Top-level objects, arrays, strings, numbers, `true`, `false`, and `null`
- Strict brackets, commas, colons, and string termination
- Standard escapes and Unicode surrogate pairs
- Optional `//` and block comments (JSONC)
- Duplicate keys, sparse arrays, circular refs, and non-string Map keys rejected
- Parse errors with line, column, and character offset

## Quick Start

Requires AutoHotkey v2. Copy [`AHK20_JSON.ahk`](AHK20_JSON.ahk) next to your script. (The repository is [`aiascendlab/ahk20-json`](https://github.com/aiascendlab/ahk20-json); the library file and class are `AHK20_JSON.ahk` / `JSON`.)

```ahk
#Requires AutoHotkey v2.0
#Include AHK20_JSON.ahk

jsonText :=
(
'{
  "name": "AHK Office Automation",
  "enabled": true,
  "nothing": null,
  "hotkeys": {
    "open": "#o"
  }
}'
)

config := JSON.Parse(jsonText)

MsgBox(config["name"])
MsgBox(config["hotkeys"]["open"])

if JSON.IsTrue(config["enabled"]) {
    MsgBox("enabled is JSON true")
}

if JSON.IsNull(config["nothing"]) {
    MsgBox("nothing is JSON null")
}

MsgBox(JSON.Stringify(config))
```

The last `MsgBox` shows:

```json
{
  "enabled": true,
  "hotkeys": {
    "open": "#o"
  },
  "name": "AHK Office Automation",
  "nothing": null
}
```

Keys come out in `Map` iteration order (sorted), not input order. `JSON.Stringify(config, 0)` gives the compact form on one line.

A CI-safe stdout example is [`examples/basic.ahk`](examples/basic.ahk). Full API: [`docs/api.md`](docs/api.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [API](docs/api.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Changelog](CHANGELOG.md)

## Project Status

**Active.** Supports AutoHotkey v2.0+. Current version is `JSON.Version` (`1.0.0`).

AHK `true`/`false` are integers `1`/`0`. Emit JSON booleans with `JSON.true`, `JSON.false`, or `JSON.Bool(value)`. Prefer `asMap := true`.

## Roadmap

1.x is a strict RFC 8259 implementation and stays that way: bug fixes, conformance fixes, and documentation. No non-standard extensions beyond the existing opt-in JSONC comments are planned. Proposals go through [Feature Request](https://github.com/aiascendlab/ahk20-json/issues/new/choose) issues.

## Tests

```powershell
# Unit tests + examples/basic.ahk (same command CI uses)
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\check.ps1

# Optional: nst/JSONTestSuite (318 files)
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\check.ps1 -Suite
```

JSONTestSuite `test_parsing`: **318 cases, 283 PASS / 0 FAIL / 35 INFO**.

## Contributing

Bug reports and small fixes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Do not open a public issue for vulnerabilities. See [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 AI Ascend Lab.

Parsing samples under `test/JSONTestSuite/` remain under the MIT license of [nst/JSONTestSuite](https://github.com/nst/JSONTestSuite). See [NOTICE](NOTICE) and [test/JSONTestSuite/LICENSE](test/JSONTestSuite/LICENSE).
