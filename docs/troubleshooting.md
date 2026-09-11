# Troubleshooting

## `true` became `1` after Stringify

AHK `true` and `false` are integers. Use `JSON.true`, `JSON.false`, or `JSON.Bool(value)`.

## Object keys disappeared or cannot be looked up

Default `asMap := true` stores objects as `Map`. Access with `obj["key"]`, not `obj.key`.

Plain `Object` (`asMap := false`) cannot represent every JSON key (for example `Base`). Prefer Map.

## Comments were rejected

Comments are off by default (RFC 8259). Pass `allowComments := true` for JSONC.

## File with a trailing NUL was accepted or looked like `123`

Raw `U+0000` is not JSON whitespace. `JSON.Parse` rejects `123` + NUL.

Do not use `FileRead(path, "UTF-8")` on JSONTestSuite samples: some files are invalid UTF-8 or contain NUL. Use the adapter in `test/JSONTestAdapter.ahk`, or read raw bytes.

AHK `InStr(haystack, Chr(0))` treats NUL as an empty needle. Do not detect whitespace with `InStr(" `t`r`n", ch)`.

## Duplicate keys

By default the second `"a"` in `{"a":1,"a":2}` is an error. That is intentional for config files.

## Unclosed `{` or `[` used to parse

This library rejects incomplete containers. That is required by RFC 8259 and safer for configs.

## Parse error location

Messages look like:

```text
Unexpected content after the JSON root value.
Line: 1, column: 4, offset: 4.
Nearby text: 123
```
