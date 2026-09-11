#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include %A_ScriptDir%\..\AHK20_JSON.ahk

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

if config["name"] != "AHK Office Automation" {
    throw Error("Parse failed: name")
}

if !JSON.IsTrue(config["enabled"]) {
    throw Error("Parse failed: enabled")
}

if !JSON.IsNull(config["nothing"]) {
    throw Error("Parse failed: nothing")
}

if config["hotkeys"]["open"] != "#o" {
    throw Error("Parse failed: hotkeys.open")
}

output := JSON.Stringify(config)
restored := JSON.Parse(output)

if restored["name"] != config["name"] {
    throw Error("Round-trip failed")
}

FileAppend("examples/basic.ahk ok`n", "*")
ExitApp(0)
