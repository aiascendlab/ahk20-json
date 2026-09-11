#Requires AutoHotkey v2.0
#Include ..\AHK20_JSON.ahk

; Interactive MsgBox demo. CI uses examples/basic.ahk instead.

jsonText :=
    (
        '{
  "name": "AHK Office Automation",
  "enabled": true,
  "nothing": null,
  "hotkeys": {
    "open": "#o",
    "search": "^!s"
  },
  "items": [
    1,
    2,
    {
      "name": "test"
    }
  ]
}'
    )

config := JSON.Parse(jsonText)

MsgBox(config["name"])
MsgBox(config["hotkeys"]["open"])
MsgBox(config["items"][3]["name"])

if JSON.IsTrue(config["enabled"]) {
    MsgBox("enabled is JSON true")
}

if JSON.IsNull(config["nothing"]) {
    MsgBox("nothing is JSON null")
}

output := JSON.Stringify(config)
MsgBox(output)
