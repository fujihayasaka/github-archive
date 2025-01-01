// Package snakecaser converts property names to SCREAMING_SNAKE_CASE
package snakecaser

import (
	"strings"
	"unicode"
)

func Do(name string) string {
	var result strings.Builder
	prevChar := '_'
	for _, char := range name {
		if unicode.IsUpper(char) && prevChar != '_' {
			result.WriteRune('_')
		}

		result.WriteRune(unicode.ToUpper(char))
		prevChar = char
	}
	return result.String()
}
