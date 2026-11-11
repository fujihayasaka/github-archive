// Package utils provides utility functions and types for autovalidation processes.
package utils

import (
	"strconv"
	"strings"
)

// PrependLineNumbersWithStartLine prefixes each line with an incrementing line
// number starting at startLine.
func PrependLineNumbersWithStartLine(code string, startLine int) string {
	lines := strings.Split(code, "\n")
	for i, line := range lines {
		lines[i] = strconv.Itoa(startLine+i) + ":" + line
	}
	return strings.Join(lines, "\n")
}
