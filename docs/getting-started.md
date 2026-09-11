# Getting started

AHK20_JSON is a single AutoHotkey v2 script. There is no package install.

## Requirements

- AutoHotkey v2.0 or later
- Windows (AutoHotkey is Windows-only)

## Install

Copy [`AHK20_JSON.ahk`](../AHK20_JSON.ahk) next to your script:

```ahk
#Requires AutoHotkey v2.0
#Include AHK20_JSON.ahk
```

If the library lives in a parent folder:

```ahk
#Include ..\AHK20_JSON.ahk
```

## First parse and stringify

```ahk
#Requires AutoHotkey v2.0
#Include AHK20_JSON.ahk

jsonText := '{"enabled":true,"name":"demo"}'
config := JSON.Parse(jsonText)

if JSON.IsTrue(config["enabled"]) {
    MsgBox(config["name"])
}

MsgBox(JSON.Stringify(config))
```

A CI-safe stdout example is [`examples/basic.ahk`](../examples/basic.ahk). An interactive MsgBox demo is [`test/simple_test.ahk`](../test/simple_test.ahk).

## Next

- [API reference](api.md)
- [Troubleshooting](troubleshooting.md)
