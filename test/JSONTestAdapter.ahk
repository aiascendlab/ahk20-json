/************************************************************************
 * JSONTestAdapter.ahk
 *
 * Purpose:
 *   Run JSON.Parse() against a single JSONTestSuite sample file.
 *
 * Arguments:
 *   A_Args[1]: path to the test file
 *   A_Args[2]: path to the result file
 *
 * Exit codes:
 *   0: JSON.Parse() accepted the input
 *   1: JSON.Parse() rejected the input
 *   2: adapter argument error
 *
 * Notes:
 *   JSONTestSuite includes invalid UTF-8 files, so this adapter must
 *   not use:
 *
 *       FileRead(path, "UTF-8")
 *
 *   It reads raw bytes, then strictly decodes them as UTF-8 with the
 *   Windows API. Invalid UTF-8 is treated as a parse rejection.
 ***********************************************************************/

#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut

#Include ..\AHK20_JSON.ahk

if A_Args.Length < 2 {
    ExitApp(2)
}

testFile := A_Args[1]
resultFile := A_Args[2]

try {
    /*
     * JSONTestSuite samples are UTF-8 JSON text.
     * ReadStrictUTF8() rejects illegal UTF-8 byte sequences.
    */
    jsonText := ReadStrictUTF8(testFile)

    /*
     * Strict JSON mode:
     *
     * keepBoolType        := true
     * asMap               := true
     * allowComments       := false
     * rejectDuplicateKeys := false
     * maxDepth            := 256
    */
    parsedValue := JSON.Parse(
        jsonText,
        true,
        true,
        false,
        false,
        256
    )

    WriteResult(
        resultFile,
        "ACCEPT",
        "",
        ""
    )

    ExitApp(0)
} catch Error as err {
    WriteResult(
        resultFile,
        "REJECT",
        Type(err),
        err.Message
    )

    ExitApp(1)
}

/**
 * Read a file as raw bytes, then decode it as strict UTF-8.
 *
 * MultiByteToWideChar() with MB_ERR_INVALID_CHARS rejects illegal
 * UTF-8 instead of silently substituting replacement characters.
 */
ReadStrictUTF8(filePath) {
    static CP_UTF8 := 65001
    static MB_ERR_INVALID_CHARS := 0x00000008

    local raw
    local wideCharCount
    local wideBuffer
    local convertedCount
    local lastError
    local decoded
    local codeUnit

    raw := FileRead(filePath, "RAW")

    if raw.Size = 0 {
        return ""
    }

    wideCharCount := DllCall(
        "MultiByteToWideChar",
        "UInt", CP_UTF8,
        "UInt", MB_ERR_INVALID_CHARS,
        "Ptr", raw.Ptr,
        "Int", raw.Size,
        "Ptr", 0,
        "Int", 0,
        "Int"
    )

    if wideCharCount = 0 {
        lastError := A_LastError

        throw Error(
            "Input is not valid UTF-8."
            . " Windows error code: "
            . lastError
        )
    }

    wideBuffer := Buffer(
        wideCharCount * 2,
        0
    )

    convertedCount := DllCall(
        "MultiByteToWideChar",
        "UInt", CP_UTF8,
        "UInt", MB_ERR_INVALID_CHARS,
        "Ptr", raw.Ptr,
        "Int", raw.Size,
        "Ptr", wideBuffer.Ptr,
        "Int", wideCharCount,
        "Int"
    )

    if convertedCount = 0 {
        lastError := A_LastError

        throw Error(
            "UTF-8 conversion failed."
            . " Windows error code: "
            . lastError
        )
    }

    /*
     * StrGet truncates at the first U+0000 even when a character
     * count is supplied. Returning that truncated string would turn
     * `123` + NUL into the valid number `123`. Restore NUL characters
     * so JSON.Parse can reject them.
    */
    decoded := StrGet(
        wideBuffer.Ptr,
        convertedCount,
        "UTF-16"
    )

    if StrLen(decoded) = convertedCount {
        return decoded
    }

    decoded := ""
    loop convertedCount {
        codeUnit := NumGet(
            wideBuffer,
            (A_Index - 1) * 2,
            "UShort"
        )
        decoded .= Chr(codeUnit)
    }

    return decoded
}

/**
 * Write one test result to a temporary file.
 *
 * Format:
 *
 * ACCEPT<TAB><TAB>
 *
 * or:
 *
 * REJECT<TAB>ErrorType<TAB>ErrorMessage
 */
WriteResult(
    resultFile,
    status,
    errorType,
    errorMessage
) {
    local output

    errorType := SanitizeField(errorType)
    errorMessage := SanitizeField(errorMessage)

    output := status
        . "`t"
        . errorType
        . "`t"
        . errorMessage

    try {
        if FileExist(resultFile) {
            FileDelete(resultFile)
        }

        /*
         * Use UTF-8-RAW so a BOM cannot shift the first status field.
        */
        FileAppend(
            output,
            resultFile,
            "UTF-8-RAW"
        )
    } catch {
        /*
         * If the result file cannot be written, exit abnormally.
         * The outer runner treats that as CRASH.
        */
        ExitApp(2)
    }
}

/**
 * Replace tabs and newlines with printable escapes so the result
 * file stays on a single line.
 */
SanitizeField(value) {
    local text

    text := Format("{}", value)

    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, "`t", "\t")
    text := StrReplace(text, "`r", "\r")
    text := StrReplace(text, "`n", "\n")

    return text
}
