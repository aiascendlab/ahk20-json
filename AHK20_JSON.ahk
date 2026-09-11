/************************************************************************
 * @description:
 *   Strict JSON parser (RFC 8259) and serializer for AutoHotkey v2.
 * 
 * @features:
 *   1. Accepts JSON objects, arrays, strings, numbers, true, false, and null
 *      as top-level values
 *   2. Strictly checks brackets, commas, colons, and string termination
 *   3. Strictly validates JSON number syntax
 *   4. Handles standard JSON escapes
 *   5. Handles Unicode surrogate pairs
 *   6. Optional // and block comments
 *   7. Rejects duplicate object keys by default
 *   8. Detects circular references
 *   9. Detects sparse arrays
 *  10. Rejects non-string Map keys
 *  11. Rejects object types that cannot be converted to JSON
 *  12. Reports line, column, and character offset on parse errors
 *  13. Does not treat U+0000 as whitespace or a string terminator
 * 
 * @version 1.0.0
 * @requires AutoHotkey v2.0
 ***********************************************************************/

class JSON {
    /*
     * Library version. Keep in sync with the file-header @version
     * and the latest heading in CHANGELOG.md.
    */
    static Version := "1.0.0"

    /*
     * JSON sentinel values.
     *
     * AutoHotkey v2 has no distinct Boolean or Null types, so ComValue
     * is used to represent JSON true, false, and null.
    */
    static null := ComValue(1, 0)
    static true := ComValue(0xB, 1)
    static false := ComValue(0xB, 0)

    /**
     * Convert a truthy AHK value to a JSON boolean.
     * 
     * @param value Any value usable as a boolean condition.
     * @returns JSON.true or JSON.false.
     */
    static Bool(value) {
        return value ? this.true : this.false
    }

    /**
     * Return whether a value is JSON.true.
     */
    static IsTrue(value) {
        return IsObject(value)
        && ObjPtr(value) = ObjPtr(this.true)
    }

    /**
     * Return whether a value is JSON.false.
     */
    static IsFalse(value) {
        return IsObject(value)
        && ObjPtr(value) = ObjPtr(this.false)
    }

    /**
     * Return whether a value is JSON.null.
     */
    static IsNull(value) {
        return IsObject(value)
        && ObjPtr(value) = ObjPtr(this.null)
    }

    /**
     * Parse JSON text into an AutoHotkey value.
     * 
     * @param text
     *   JSON text to parse.
     * 
     * @param keepBoolType
     *   true:
     *     JSON true  -> JSON.true
     *     JSON false -> JSON.false
     *     JSON null  -> JSON.null
     * 
     *   false:
     *     JSON true  -> 1
     *     JSON false -> 0
     *     JSON null  -> ""
     * 
     * @param asMap
     *   true: JSON objects become Map values.
     *   false: JSON objects become plain Objects.
     * 
     *   Prefer true in all cases.
     * 
     * @param allowComments
     *   When true, allow:
     *     // line comments
     *     block comments
     * 
     *   That is JSONC, not strict JSON.
     * 
     * @param rejectDuplicateKeys
     *   When true, reject duplicate keys in the same object.
     * 
     * @param maxDepth
     *   Maximum nesting depth.
     * 
     * @returns The parsed AHK value.
     */
    static Parse(
        text,
        keepBoolType := true,
        asMap := true,
        allowComments := false,
        rejectDuplicateKeys := true,
        maxDepth := 256
    ) {
        if Type(text) != "String" {
            throw TypeError(
                "JSON.Parse text must be a String, got: "
                Type(text)
            )
        }

        if Type(maxDepth) != "Integer" || maxDepth < 1 {
            throw ValueError(
                "JSON.Parse maxDepth must be an integer greater than 0."
            )
        }

        /*
         * FileRead(path, "UTF-8") usually strips a BOM.
         * Also drop a leftover U+FEFF if one is still present.
        */
        if SubStr(text, 1, 1) = Chr(0xFEFF) {
            text := SubStr(text, 2)
        }

        pos := 1
        textLength := StrLen(text)

        jsonTrue := keepBoolType ? this.true : true
        jsonFalse := keepBoolType ? this.false : false
        jsonNull := keepBoolType ? this.null : ""

        SkipIgnored()

        if pos > textLength {
            Fail("JSON text is empty.")
        }

        /*
         * Do not name this variable result.
         *
         * Nested functions in AHK v2 form closures. Distinct names
         * avoid capturing ParseArray() / ParseObject() result
         * variables:
         *
         * rootValue
         * arrayResult
         * objectResult
        */
        rootValue := ParseValue(0)

        SkipIgnored()

        if pos <= textLength {
            Fail("Unexpected content after the JSON root value.")
        }

        return rootValue

        /**
         * Return the character at the current position, or an offset.
         */
        Peek(offset := 0) {
            return SubStr(text, pos + offset, 1)
        }

        /**
         * Throw an error with line, column, offset, and nearby text.
         */
        Fail(message) {
            local safePos
            local prefix
            local line
            local lastLF
            local column
            local contextStart
            local context

            safePos := Min(Max(pos, 1), textLength + 1)
            prefix := SubStr(text, 1, safePos - 1)

            line := StrLen(prefix)
            - StrLen(StrReplace(prefix, "`n"))
            + 1

            lastLF := InStr(prefix, "`n", true, -1)

            column := lastLF
                ? StrLen(prefix) - lastLF + 1
                    : StrLen(prefix) + 1

            contextStart := Max(1, safePos - 20)
            context := SubStr(text, contextStart, 40)

            context := StrReplace(context, "\", "\\")
            context := StrReplace(context, "`r", "\r")
            context := StrReplace(context, "`n", "\n")
            context := StrReplace(context, "`t", "\t")

            throw Error(
                message
                . "`nLine: " line
                . ", column: " column
                . ", offset: " safePos
                . "."
                . "`nNearby text: " context
            )
        }

        /**
         * Skip JSON whitespace and, optionally, JSONC comments.
         */
        SkipIgnored() {
            local pair
            local endPos
            local ch

            loop {
                /*
                 * JSON allows only these four whitespace characters:
                 *
                 * U+0020 space
                 * U+0009 Tab
                 * U+000D CR
                 * U+000A LF
                 *
                 * Do not use InStr(" `t`r`n", ch).
                 * AHK treats Chr(0) as an empty needle, so InStr
                 * returns 1 and a trailing NUL after a complete value
                 * (for example 123 + NUL) would be skipped as space.
                */
                while pos <= textLength {
                    ch := Peek()
                    if ch != " "
                        && ch != "`t"
                        && ch != "`r"
                        && ch != "`n" {
                        break
                    }
                    pos += 1
                }

                if !allowComments || pos > textLength {
                    return
                }

                pair := SubStr(text, pos, 2)

                /*
                 * Line comment.
                */
                if pair = "//" {
                    pos += 2

                    while pos <= textLength
                        && Peek() != "`r"
                        && Peek() != "`n" {
                        pos += 1
                    }

                    continue
                }

                /*
                 * Block comment.
                */
                if pair = "/*" {
                    endPos := InStr(text, "*/", true, pos + 2)

                    if !endPos {
                        Fail("Unterminated JSON block comment.")
                    }

                    pos := endPos + 2
                    continue
                }

                return
            }
        }

        /**
         * Parse any JSON value.
         */
        ParseValue(depth) {
            local ch

            SkipIgnored()

            if pos > textLength {
                Fail("Missing JSON value.")
            }

            ch := Peek()

            switch ch {
                case "{":
                    return ParseObject(depth + 1)

                case "[":
                    return ParseArray(depth + 1)

                case '"':
                    return ParseString()

                case "t":
                    return ParseLiteral("true", jsonTrue)

                case "f":
                    return ParseLiteral("false", jsonFalse)

                case "n":
                    return ParseLiteral("null", jsonNull)

                default:
                    if ch = "-" || RegExMatch(ch, "^\d$") {
                        return ParseNumber()
                    }

                    Fail("Unrecognized JSON character: " ch)
            }
        }

        /**
         * Parse true, false, or null.
         */
        ParseLiteral(word, returnValue) {
            if SubStr(text, pos, StrLen(word)) != word {
                Fail("Invalid JSON literal.")
            }

            pos += StrLen(word)
            return returnValue
        }

        /**
         * Parse a strict JSON number.
         */
        ParseNumber() {
            local remaining
            local match
            local token
            local numberValue
            local formatted
            local mantissa

            remaining := SubStr(text, pos)

            /*
             * Standard JSON number syntax:
             *
             * - optional minus sign
             * - integer part is 0, or starts with a non-zero digit
             * - optional fraction; digits are required after the dot
             * - optional exponent; the sign is optional
            */
            if !RegExMatch(
                remaining,
                "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?",
                &match
            ) {
                Fail("Invalid JSON number.")
            }

            token := match[0]
            pos += StrLen(token)

            try {
                numberValue := token + 0
            } catch Error {
                Fail(
                    "JSON number cannot be converted to an AutoHotkey number: "
                    token
                )
            }

            /*
             * A JSON number with no fraction and no exponent should
             * become an AHK Integer.
             *
             * If conversion yields a Float, the value is outside AHK's
             * 64-bit integer range. Reject it so large integers in
             * config files are not silently rounded.
            */
            if !InStr(token, ".")
            && !InStr(token, "e", false)
            && Type(numberValue) != "Integer" {
                Fail(
                    "JSON integer is outside the AutoHotkey 64-bit integer range: "
                    token
                )
            }

            if Type(numberValue) = "Float" {
                /*
                 * Reject Infinity, NaN, and other non-JSON results.
                */
                formatted := Format("{:.17g}", numberValue)

                if !RegExMatch(
                    formatted,
                    "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$"
                ) {
                    Fail(
                        "JSON floating-point number is outside the AutoHotkey range: "
                        token
                    )
                }

                /*
                 * Reject non-zero floats that underflow to 0.
                */
                mantissa := RegExReplace(token, "[eE].*$")

                if numberValue = 0
                    && RegExMatch(mantissa, "[1-9]") {
                    Fail(
                        "JSON floating-point number underflows to zero: "
                        token
                    )
                }
            }

            return numberValue
        }

        /**
         * Parse a JSON string.
         */
        ParseString() {
            local output
            local ch
            local code
            local escape
            local hex
            local codePoint
            local lowHex
            local lowCodePoint

            if Peek() != '"' {
                Fail("JSON string is missing its opening quote.")
            }

            pos += 1
            output := ""

            while pos <= textLength {
                ch := Peek()
                pos += 1

                if ch = '"' {
                    return output
                }

                code := Ord(ch)

                /*
                 * Unescaped U+0000 through U+001F control characters
                 * are not allowed in JSON strings.
                */
                if code < 0x20 {
                    Fail(
                        "JSON string contains an unescaped control character."
                    )
                }

                if ch != "\" {
                    output .= ch
                    continue
                }

                if pos > textLength {
                    Fail("JSON string ends with an incomplete escape.")
                }

                escape := Peek()
                pos += 1

                switch escape {
                    case '"':
                        output .= '"'

                    case "\":
                        output .= "\"

                    case "/":
                        output .= "/"

                    case "b":
                        output .= "`b"

                    case "f":
                        output .= "`f"

                    case "n":
                        output .= "`n"

                    case "r":
                        output .= "`r"

                    case "t":
                        output .= "`t"

                    case "u":
                        hex := SubStr(text, pos, 4)

                        if StrLen(hex) != 4
                        || !RegExMatch(
                            hex,
                            "i)^[0-9a-f]{4}$"
                        ) {
                            Fail("Invalid JSON \uXXXX escape.")
                        }

                        codePoint := Integer("0x" hex)
                        pos += 4

                        /*
                         * UTF-16 high surrogate.
                        */
                        if codePoint >= 0xD800
                            && codePoint <= 0xDBFF {

                            if SubStr(text, pos, 2) != "\u" {
                                Fail(
                                    "Unicode high surrogate is not followed by a low surrogate."
                                )
                            }

                            lowHex := SubStr(text, pos + 2, 4)

                            if StrLen(lowHex) != 4
                            || !RegExMatch(
                                lowHex,
                                "i)^[0-9a-f]{4}$"
                            ) {
                                Fail(
                                    "Invalid Unicode low surrogate."
                                )
                            }

                            lowCodePoint := Integer("0x" lowHex)

                            if lowCodePoint < 0xDC00
                                || lowCodePoint > 0xDFFF {
                                Fail(
                                    "Unicode surrogate pair is mismatched."
                                )
                            }

                            pos += 6

                            codePoint := 0x10000
                                + (
                                    (codePoint - 0xD800)
                                    << 10
                                )
                                + (
                                    lowCodePoint - 0xDC00
                                )

                            output .= Chr(codePoint)
                            continue
                        }

                        /*
                         * Lone low surrogate with no high surrogate.
                        */
                        if codePoint >= 0xDC00
                            && codePoint <= 0xDFFF {
                            Fail(
                                "Unicode low surrogate is missing a high surrogate."
                            )
                        }

                        output .= Chr(codePoint)

                    default:
                        Fail(
                            "Unsupported JSON escape: \"
                            escape
                        )
                }
            }

            Fail("JSON string is missing its closing quote.")
        }

        /**
         * Parse a JSON array.
         */
        ParseArray(depth) {
            local arrayResult
            local ch

            if depth > maxDepth {
                Fail("JSON nesting exceeds the maximum depth.")
            }

            arrayResult := []
            pos += 1

            SkipIgnored()

            /*
             * Empty array.
            */
            if Peek() = "]" {
                pos += 1
                return arrayResult
            }

            loop {
                arrayResult.Push(ParseValue(depth))

                SkipIgnored()

                if pos > textLength {
                    Fail("Unterminated JSON array.")
                }

                ch := Peek()

                if ch = "]" {
                    pos += 1
                    return arrayResult
                }

                if ch != "," {
                    Fail("Missing comma between JSON array elements.")
                }

                pos += 1
                SkipIgnored()

                /*
                 * Strict JSON does not allow trailing commas.
                */
                if Peek() = "]" {
                    Fail("JSON arrays may not have a trailing comma.")
                }
            }
        }

        /**
         * Parse a JSON object.
         */
        ParseObject(depth) {
            local objectResult
            local key
            local memberValue
            local ch

            if depth > maxDepth {
                Fail("JSON nesting exceeds the maximum depth.")
            }

            objectResult := asMap ? Map() : {}
            pos += 1

            SkipIgnored()

            /*
             * Empty object.
            */
            if Peek() = "}" {
                pos += 1
                return objectResult
            }

            loop {
                SkipIgnored()

                if Peek() != '"' {
                    Fail(
                        "JSON object member names must be double-quoted strings."
                    )
                }

                key := ParseString()

                SkipIgnored()

                if Peek() != ":" {
                    Fail(
                        "Missing colon after JSON object member name."
                    )
                }

                pos += 1
                memberValue := ParseValue(depth)

                if asMap {
                    if rejectDuplicateKeys
                        && objectResult.Has(key) {
                        Fail(
                            "Duplicate key in JSON object: "
                            key
                        )
                    }

                    objectResult[key] := memberValue
                } else {
                    /*
                     * Base is a special property of a plain AHK Object
                     * and cannot be treated as a normal data property.
                    */
                    if StrLower(key) = "base" {
                        Fail(
                            "The Base key is not allowed in Object mode; "
                            . "use asMap := true."
                        )
                    }

                    if rejectDuplicateKeys
                        && objectResult.HasOwnProp(key) {
                        Fail(
                            "Duplicate or case-colliding key in JSON object: "
                            . key
                        )
                    }

                    objectResult.DefineProp(
                        key, {
                            Value: memberValue
                        }
                    )
                }

                SkipIgnored()

                if pos > textLength {
                    Fail("Unterminated JSON object.")
                }

                ch := Peek()

                if ch = "}" {
                    pos += 1
                    return objectResult
                }

                if ch != "," {
                    Fail(
                        "Missing comma between JSON object members."
                    )
                }

                pos += 1
                SkipIgnored()

                /*
                 * Strict JSON does not allow trailing commas.
                */
                if Peek() = "}" {
                    Fail("JSON objects may not have a trailing comma.")
                }
            }
        }
    }

    /**
     * Serialize an AutoHotkey value to JSON text.
     * 
     * @param value
     *   Value to convert.
     * 
     * @param expandLevel
     *   Maximum depth to pretty-print.
     * 
     *   Unspecified: pretty-print every level.
     *   0: fully compact.
     *   1: pretty-print the root level only.
     * 
     * @param space
     *   Indentation string for each level. Default is two spaces.
     * 
     * @param maxDepth
     *   Maximum nesting depth.
     */
    static Stringify(
        value,
        expandLevel := unset,
        space := "  ",
        maxDepth := 256
    ) {
        local active
        local jsonText

        if !IsSet(expandLevel) {
            expandLevel := 10000000
        } else {
            if !IsNumber(expandLevel) {
                throw TypeError(
                    "JSON.Stringify expandLevel must be a number."
                )
            }

            expandLevel := Abs(expandLevel)
        }

        if Type(space) != "String" {
            throw TypeError(
                "JSON.Stringify space must be a String."
            )
        }

        if Type(maxDepth) != "Integer" || maxDepth < 1 {
            throw ValueError(
                "JSON.Stringify maxDepth "
                . "must be an integer greater than 0."
            )
        }

        /*
         * Track containers on the current recursion path.
         *
         * Only the current path is checked. The same object may still
         * be shared from different locations.
        */
        active := Map()

        jsonText := Encode(value, 0, "$")

        /*
         * Stringify() must always return a String, even when the root
         * value is an Integer.
        */
        return Format("{}", jsonText)

        /**
         * Encode any AHK value.
         */
        Encode(currentValue, depth, path) {
            local pointer
            local valueType

            /*
             * Identify JSON sentinels first.
            */
            if IsObject(currentValue) {
                pointer := ObjPtr(currentValue)

                if pointer = ObjPtr(JSON.null) {
                    return "null"
                }

                if pointer = ObjPtr(JSON.true) {
                    return "true"
                }

                if pointer = ObjPtr(JSON.false) {
                    return "false"
                }
            }

            valueType := Type(currentValue)

            switch valueType {
                case "String":
                    return Quote(currentValue)

                case "Integer":
                    /*
                     * AHK true and false are the integers 1 and 0.
                     *
                     * Plain true/false therefore stringify as 1/0.
                     * To emit JSON booleans, use:
                     *
                     * JSON.true
                     * JSON.false
                     * JSON.Bool(value)
                    */
                    return Format("{}", currentValue)

                case "Float":
                    return EncodeFloat(currentValue)

                case "Array":
                    return EncodeArray(
                        currentValue,
                        depth,
                        path
                    )

                case "Map":
                    return EncodeMap(
                        currentValue,
                        depth,
                        path
                    )

                case "Object":
                    return EncodeObject(
                        currentValue,
                        depth,
                        path
                    )

                default:
                    throw TypeError(
                        "JSON cannot encode type "
                        . valueType
                        . " at "
                        . path
                    )
            }
        }

        /**
         * Encode a floating-point number.
         */
        EncodeFloat(numberValue) {
            local digits
            local candidate

            /*
             * Prefer a shorter representation that round-trips to the
             * same Double.
             *
             * IEEE 754 doubles need at most 17 significant digits.
            */
            loop 3 {
                digits := 14 + A_Index

                candidate := Format(
                    "{:." digits "g}",
                    numberValue
                )

                if !RegExMatch(
                    candidate,
                    "^-?(?:0|[1-9]\d*)"
                    . "(?:\.\d+)?"
                    . "(?:[eE][+-]?\d+)?$"
                ) {
                    continue
                }

                try {
                    if candidate + 0 = numberValue {
                        /*
                         * If the original value is a Float but the
                         * formatted text looks like an integer, append
                         * .0 so parsing it again still yields a Float.
                        */
                        if !InStr(candidate, ".")
                        && !InStr(candidate, "e", false) {
                            candidate .= ".0"
                        }

                        return candidate
                    }
                }
            }

            throw ValueError(
                "JSON cannot encode NaN, Infinity, "
                . "or a floating-point value that cannot be represented reliably."
            )
        }

        /**
         * Encode an array.
         */
        EncodeArray(arrayValue, depth, path) {
            local items
            local index
            local itemPath

            CheckContainer(arrayValue, depth, path)
            items := []

            try {
                loop arrayValue.Length {
                    index := A_Index
                    itemPath := path "[" index "]"

                    if !arrayValue.Has(index) {
                        throw ValueError(
                            "JSON cannot encode sparse arrays at "
                            . itemPath
                        )
                    }

                    items.Push(
                        Encode(
                            arrayValue[index],
                            depth + 1,
                            itemPath
                        )
                    )
                }

                return Wrap(
                    "[",
                    "]",
                    items,
                    depth
                )
            } finally {
                active.Delete(arrayValue)
            }
        }

        /**
         * Encode a Map.
         */
        EncodeMap(mapValue, depth, path) {
            local items
            local key
            local memberValue
            local itemPath

            CheckContainer(mapValue, depth, path)
            items := []

            try {
                for key, memberValue in mapValue {
                    /*
                     * JSON object keys must be strings.
                     *
                     * Numeric keys are not coerced to strings, because
                     * 1 and "1" would then collide.
                    */
                    if Type(key) != "String" {
                        throw TypeError(
                            "JSON object Map keys must be strings, "
                            . "got: "
                            . Type(key)
                            . " at "
                            . path
                        )
                    }

                    itemPath := PathForKey(path, key)

                    items.Push(
                        Quote(key)
                        . Separator(depth)
                        . Encode(
                            memberValue,
                            depth + 1,
                            itemPath
                        )
                    )
                }

                return Wrap(
                    "{",
                    "}",
                    items,
                    depth
                )
            } finally {
                active.Delete(mapValue)
            }
        }

        /**
         * Encode own properties of a plain Object.
         */
        EncodeObject(objectValue, depth, path) {
            local items
            local key
            local memberValue
            local itemPath

            CheckContainer(objectValue, depth, path)
            items := []

            try {
                for key, memberValue in objectValue.OwnProps() {
                    itemPath := PathForKey(path, key)

                    items.Push(
                        Quote(key)
                        . Separator(depth)
                        . Encode(
                            memberValue,
                            depth + 1,
                            itemPath
                        )
                    )
                }

                return Wrap(
                    "{",
                    "}",
                    items,
                    depth
                )
            } finally {
                active.Delete(objectValue)
            }
        }

        /**
         * Check maximum depth and circular references.
         */
        CheckContainer(container, depth, path) {
            if depth >= maxDepth {
                throw ValueError(
                    "JSON nesting exceeds the maximum depth at "
                    . path
                )
            }

            if active.Has(container) {
                throw ValueError(
                    "Circular reference at "
                    . path
                    . "; first seen at "
                    . active[container]
                )
            }

            active[container] := path
        }

        /**
         * Build a property path for error messages.
         */
        PathForKey(parentPath, key) {
            if RegExMatch(
                key,
                "^[A-Za-z_$][A-Za-z0-9_$]*$"
            ) {
                return parentPath "." key
            }

            return parentPath "[" Quote(key) "]"
        }

        /**
         * Return the colon between a key and its value.
         */
        Separator(depth) {
            return depth < expandLevel ? ": " : ":"
        }

        /**
         * Wrap an array or object.
         */
        Wrap(
            openCharacter,
            closeCharacter,
            items,
            depth
        ) {
            local pretty
            local itemIndentation
            local closingIndentation

            if items.Length = 0 {
                return openCharacter closeCharacter
            }

            pretty := depth < expandLevel

            if !pretty {
                return openCharacter
                    . Join(items, ",")
                    . closeCharacter
            }

            itemIndentation := Indent(depth + 1)
            closingIndentation := Indent(depth)

            return openCharacter
                . "`n"
                . itemIndentation
                . Join(
                    items,
                    ",`n" itemIndentation
                )
                . "`n"
                . closingIndentation
                . closeCharacter
        }

        /**
         * Build indentation.
         */
        Indent(level) {
            local output

            output := ""

            loop level {
                output .= space
            }

            return output
        }

        /**
         * Join an array of strings.
         */
        Join(items, separator) {
            local output
            local index
            local item

            output := ""

            for index, item in items {
                if index > 1 {
                    output .= separator
                }

                output .= item
            }

            return output
        }

        /**
         * Encode a string as a strict JSON string.
         */
        Quote(stringValue) {
            local output
            local length
            local index
            local ch
            local code
            local lowCharacter
            local lowCode

            output := ""
            length := StrLen(stringValue)
            index := 1

            while index <= length {
                ch := SubStr(stringValue, index, 1)
                code := Ord(ch)

                /*
                 * AHK strings are UTF-16.
                 * Keep valid surrogate pairs; reject lone surrogates.
                */
                if code >= 0xD800 && code <= 0xDBFF {
                    if index >= length {
                        throw ValueError(
                            "String contains a lone Unicode high surrogate."
                        )
                    }

                    lowCharacter := SubStr(
                        stringValue,
                        index + 1,
                        1
                    )

                    lowCode := Ord(lowCharacter)

                    if lowCode < 0xDC00
                        || lowCode > 0xDFFF {
                        throw ValueError(
                            "String contains an invalid Unicode surrogate pair."
                        )
                    }

                    output .= ch lowCharacter
                    index += 2
                    continue
                }

                if code >= 0xDC00 && code <= 0xDFFF {
                    throw ValueError(
                        "String contains a lone Unicode low surrogate."
                    )
                }

                switch code {
                    /*
                     * Double quote.
                    */
                    case 0x22:
                        output .= '\"'

                        /*
                         * Backslash.
                        */
                    case 0x5C:
                        output .= "\\"

                        /*
                         * Backspace.
                        */
                    case 0x08:
                        output .= "\b"

                        /*
                         * Tab.
                        */
                    case 0x09:
                        output .= "\t"

                        /*
                         * LF.
                        */
                    case 0x0A:
                        output .= "\n"

                        /*
                         * Form Feed.
                        */
                    case 0x0C:
                        output .= "\f"

                        /*
                         * CR.
                        */
                    case 0x0D:
                        output .= "\r"

                    default:
                        /*
                         * Remaining U+0000 through U+001F controls
                         * use \uXXXX.
                         *
                         * This includes vertical tab U+000B; do not
                         * emit the illegal \v escape.
                        */
                        if code < 0x20 {
                            output .= Format(
                                "\u{:04X}",
                                code
                            )
                        } else {
                            output .= ch
                        }
                }

                index += 1
            }

            return '"' output '"'
        }
    }
}
