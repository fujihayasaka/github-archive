// Package helpers contains helper functions that are used across the codebase.
package helpers

import (
	"reflect"
	"runtime"
	"strings"
)

// GetFunctionName returns the name of the function.
func GetFunctionName(i interface{}) string {
	if i == nil {
		return ""
	}

	return runtime.FuncForPC(reflect.ValueOf(i).Pointer()).Name()
}

// ContainsWholeWord checks if a string contains a whole word.
func ContainsWholeWord(stringToSearch, searchedWord, separator string) bool {
	words := strings.Split(stringToSearch, separator)
	for _, word := range words {
		if word == searchedWord {
			return true
		}
	}
	return false
}

// RemoveDuplicates removes duplicate strings from a slice.
func RemoveDuplicates(elements []string) []string {
	seen := make(map[string]bool)
	result := []string{}

	for _, element := range elements {
		if !seen[element] {
			seen[element] = true
			result = append(result, element)
		}
	}

	return result
}
