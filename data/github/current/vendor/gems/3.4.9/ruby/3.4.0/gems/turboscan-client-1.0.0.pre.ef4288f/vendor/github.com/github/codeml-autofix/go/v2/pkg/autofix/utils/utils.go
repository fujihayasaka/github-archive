// Package utils is a package that provides utility functions for working with code snippets.
package utils

import (
	"path/filepath"
	"regexp"
	"strings"
)

const (
	// TabSize represents number of spaces a tab is worth
	TabSize = 4
)

var (
	// indentationRegexp is a regular expression that matches the indentation of a line.
	indentationRegexp = regexp.MustCompile(`^[ \t]*`)
)

// GetIndentation gets the indentation for the first line in the given text.
func GetIndentation(text string) string {
	return indentationRegexp.FindString(text)
}

// GetEffectiveIndentation gets a number representing the indentation of a line.
// Spaces count for 1, tabs count for TabSize.
// Blank lines are assumed to have the same indentation as the next non-blank line.
// Returns 0 if no non-blank lines are found after lineNumber.
// Note lineNumber is 0-based here (TODO refactor?)
func GetEffectiveIndentation(lines []string, lineNumber int) int {
	if lineNumber < 0 || lineNumber >= len(lines) {
		return 0
	}

	for i := lineNumber; i < len(lines); i++ {
		line := lines[i]
		if !IsBlank(line) {
			indentationStr := GetIndentation(line)
			return len(strings.ReplaceAll(indentationStr, "\t", strings.Repeat(" ", TabSize)))
		}
	}
	return 0
}

// IsBlank checks if a line contains only whitespace.
// TrimSpace is used to remove leading and trailing whitespace including newlines, tabs, and spaces.
func IsBlank(line string) bool {
	return strings.TrimSpace(line) == ""
}

// NormalizeLineEndings normalizes line endings to \n.
// Returns the normalized string.
func NormalizeLineEndings(str string) string {
	return strings.ReplaceAll(str, "\r\n", "\n")
}

// NormalizeFilePathForPlatform normalizes a file path for windows style.
func NormalizeFilePathForPlatform(path string) string {
	return filepath.FromSlash(path)
}
