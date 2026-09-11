#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\AHK20_JSON.ahk

OnError(ExitOnError)

ExitOnError(err, *) {
    FileAppend(err.Message "`n", "*")
    ExitApp(1)
}

Assert(condition, message) {
    if !condition
        throw Error("Test failed: " message)
}

AssertThrows(callback, message) {
    try {
        callback()
    } catch {
        return
    }

    throw Error("Test failed, expected an exception: " message)
}

; =========================================================
; Version
; =========================================================

Assert(
    RegExMatch(JSON.Version, "^\d+\.\d+\.\d+$"),
    "JSON.Version is MAJOR.MINOR.PATCH"
)

libraryText := FileRead(A_ScriptDir "\..\AHK20_JSON.ahk", "UTF-8")
if !RegExMatch(libraryText, "m)^\s*\*\s*@version\s+(\S+)", &headerVersion) {
    throw Error("AHK20_JSON.ahk is missing an @version header.")
}

Assert(
    headerVersion[1] = JSON.Version,
    "file-header @version matches JSON.Version"
)

changelogText := FileRead(A_ScriptDir "\..\CHANGELOG.md", "UTF-8")
Assert(
    RegExMatch(changelogText, "m)^## \[\Q" JSON.Version "\E\]"),
    "CHANGELOG.md has a heading for JSON.Version"
)

; =========================================================
; Valid JSON
; =========================================================

Assert(JSON.Parse("123") = 123, "top-level integer")
Assert(JSON.Parse("-12.5") = -12.5, "top-level float")
Assert(JSON.Parse('"hello"') = "hello", "top-level string")

Assert(
    ObjPtr(JSON.Parse("true")) = ObjPtr(JSON.true),
    "top-level true"
)

Assert(
    ObjPtr(JSON.Parse("false")) = ObjPtr(JSON.false),
    "top-level false"
)

Assert(
    ObjPtr(JSON.Parse("null")) = ObjPtr(JSON.null),
    "top-level null"
)

a := JSON.Parse('[0,-0,1.5,1e2,1E-2,1e+2]')
Assert(a.Length = 6, "valid number array")

unicode := JSON.Parse('"\u4E2D\u6587"')
Assert(unicode = Chr(0x4E2D) Chr(0x6587), "BMP Unicode")

emoji := JSON.Parse('"\uD83D\uDE00"')
Assert(emoji = "😀", "Unicode surrogate pair")

escaped := JSON.Parse('"\"\\\/\b\f\n\r\t"')
Assert(InStr(escaped, "/"), "slash escape")

obj := JSON.Parse('{"a":1,"b":[true,null,"x"]}')
Assert(obj["a"] = 1, "object property")
Assert(obj["b"].Length = 3, "nested array")

; =========================================================
; Invalid JSON
; =========================================================

invalidInputs := [
    "",
    "{",
    "[",
    '{"a":1',
    "[1,2",
    '{"a":[1,2}',
    '{"a":1]',
    "[1]]",
    "[]{}",
    '{"a":1} garbage',
    "[1,]",
    '{"a":1,}',
    "[1 2]",
    '{"a":1 "b":2}',
    "[01]",
    "[+1]",
    "[.5]",
    "[1.]",
    "[1e]",
    "[1e+]",
    '[1e-]',
    '["\a"]',
    '["\v"]',
    '["\x41"]',
    '["\q"]',
    '["\u123"]',
    '["\u12G4"]',
    '["\uD83D"]',
    '["\uDE00"]'
]

for input in invalidInputs {
    AssertThrows(
        () => JSON.Parse(input),
        "should reject: " input
    )
}

; Raw control characters must be rejected.
AssertThrows(
    () => JSON.Parse('"a' Chr(1) 'b"'),
    "unescaped control character"
)

AssertThrows(
    () => JSON.Parse('"a' "`n" 'b"'),
    "raw newline inside a string"
)

; A bare NUL after the root value must be rejected. AHK InStr treats
; Chr(0) as an empty needle, so NUL must not be skipped as whitespace.
AssertThrows(
    () => JSON.Parse("123" Chr(0)),
    "NUL after a number"
)

AssertThrows(
    () => JSON.Parse("[]" Chr(0)),
    "NUL after an array"
)

AssertThrows(
    () => JSON.Parse(Chr(0)),
    "NUL alone"
)

; Comments are rejected by default.
AssertThrows(
    () => JSON.Parse('{"a":1 // comment`n}'),
    "comments rejected by default"
)

; Comments can be enabled explicitly.
commented := JSON.Parse(
    '{"a":1, /* comment */ "b":2}',
    true,
    true,
    true
)

Assert(commented["b"] = 2, "comments allowed when enabled")

; Duplicate keys are rejected by default.
AssertThrows(
    () => JSON.Parse('{"a":1,"a":2}'),
    "duplicate key"
)

; =========================================================
; Stringify
; =========================================================

data := Map(
    "enabled", JSON.true,
    "disabled", JSON.false,
    "nothing", JSON.null,
    "number", 123,
    "text", "hello",
    "control", Chr(1) Chr(11) Chr(27)
)

text := JSON.Stringify(data)
restored := JSON.Parse(text)

Assert(
    ObjPtr(restored["enabled"]) = ObjPtr(JSON.true),
    "true round-trip"
)

Assert(
    ObjPtr(restored["disabled"]) = ObjPtr(JSON.false),
    "false round-trip"
)

Assert(
    ObjPtr(restored["nothing"]) = ObjPtr(JSON.null),
    "null round-trip"
)

; Output must not contain the illegal \v escape.
Assert(!InStr(text, "\v"), "must not emit illegal \v")
Assert(InStr(text, "\u000B"), "vertical tab must be \u000B")

; Non-string Map keys must be rejected.
AssertThrows(
    () => JSON.Stringify(Map(1, "one")),
    "non-string Map key"
)

; Unsupported types must be rejected.
AssertThrows(
    () => JSON.Stringify(Map("buffer", Buffer(10))),
    "unsupported type"
)

; Sparse arrays must be rejected.
sparse := []
sparse.Length := 3
sparse[2] := "x"

AssertThrows(
    () => JSON.Stringify(sparse),
    "sparse array"
)

; Circular references must be rejected.
circular := Map()
circular["self"] := circular

AssertThrows(
    () => JSON.Stringify(circular),
    "circular reference"
)

FileAppend("All JSON tests passed.`n", "*")
ExitApp(0)
