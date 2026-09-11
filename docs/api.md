# API

Public surface: class `JSON` in [`AHK20_JSON.ahk`](../AHK20_JSON.ahk).

## Version

```ahk
JSON.Version  ; "1.0.0"
```

Must match the `@version` header in `AHK20_JSON.ahk` and the latest `## [x.y.z]` heading in `CHANGELOG.md`.

## Sentinels

AutoHotkey v2 has no distinct Boolean or Null types. JSON uses `ComValue` sentinels:

```ahk
JSON.true
JSON.false
JSON.null
JSON.Bool(value)      ; truthy → JSON.true, otherwise JSON.false
JSON.IsTrue(value)
JSON.IsFalse(value)
JSON.IsNull(value)
```

Native AHK `true` / `false` are the integers `1` / `0`. `JSON.Stringify(true)` emits `1`, not `true`. Use `JSON.true` or `JSON.Bool()`.

## Parse

```ahk
JSON.Parse(text, keepBoolType := true, asMap := true, allowComments := false, rejectDuplicateKeys := true, maxDepth := 256)
```

| Parameter | Default | Meaning |
|---|---|---|
| `text` | required | JSON string |
| `keepBoolType` | `true` | `true`/`false`/`null` → sentinels; if `false` → `1` / `0` / `""` |
| `asMap` | `true` | Objects become `Map`. Prefer this. |
| `allowComments` | `false` | `//` and `/* */` (JSONC, not strict JSON) |
| `rejectDuplicateKeys` | `true` | Reject duplicate keys in one object |
| `maxDepth` | `256` | Maximum nesting |

Errors include line, column, character offset, and nearby text.

## Stringify

```ahk
JSON.Stringify(value, expandLevel := unset, space := "  ", maxDepth := 256)
```

| Parameter | Default | Meaning |
|---|---|---|
| `value` | required | AHK value |
| `expandLevel` | unset (pretty-print all levels) | `0` = compact; `1` = root level only |
| `space` | `"  "` | Indent string |
| `maxDepth` | `256` | Maximum nesting |

Rejected: circular references, sparse arrays, non-string Map keys, unsupported types, integers outside AHK 64-bit range, non-finite floats.
