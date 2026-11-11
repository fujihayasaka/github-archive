package parser

import (
	"regexp"
	"strings"
	"unicode/utf8"
)

func IsPossibleGlobExpression(input string) bool {
	return strings.ContainsRune(input, '?') || strings.ContainsRune(input, '*')
}

func ConvertGlobToRegex(input string) string {
	output := ""

	if strings.HasPrefix(input, "/") {
		input = input[1:]
		output += "^"
	} else if strings.HasPrefix(input, "**/") {
		input = input[3:]
		output += ".*(^|/)"
	} else {
		output += "(^|/)"
	}

	idx := 0
	for idx < len(input) {
		ch, size := utf8.DecodeRuneInString(input[idx:])

		if ch == '?' {
			output += "."
		} else if ch == '*' {
			// Note: since '*' is a single byte, we don't have to decode a whole rune
			if idx+1 < len(input) && input[idx+1] == '*' {
				idx++
				output += ".*"
			} else {
				output += "[^/]*"
			}
		} else if ch == '\\' {
			if idx+1 < len(input) && (input[idx+1] == '?' || input[idx+1] == '*' || input[idx+1] == '\\') {
				output += regexp.QuoteMeta(string(input[idx+1]))
				idx++
			} else {
				output += regexp.QuoteMeta(string(ch))
			}
		} else {
			output += regexp.QuoteMeta(string(ch))
		}

		idx += size
	}

	output += "$"
	return output
}
