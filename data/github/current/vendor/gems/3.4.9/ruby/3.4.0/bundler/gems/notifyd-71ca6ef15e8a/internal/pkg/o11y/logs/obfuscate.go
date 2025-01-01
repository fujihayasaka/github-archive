package logs

import (
	"fmt"
)

// Obfuscate will obfuscate a string longer than 8 characters
//
// Example:
//
//	"abcdefghijkl" -> "abcd...ijkl"
func Obfuscate(str string) string {
	if len(str) < 8 {
		return str
	}

	return fmt.Sprintf("%s...%s", str[0:4], str[len(str)-4:])
}
