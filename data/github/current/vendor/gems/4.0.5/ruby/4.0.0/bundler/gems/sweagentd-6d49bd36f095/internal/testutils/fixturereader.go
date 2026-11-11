// Package testutils provides utility functions for testing.
package testutils

import (
	"fmt"
	"os"
)

// ReadFixture reads the contents of a file at the given path and returns it as a string.
func ReadFixture(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Sprintf("Failed to read fixture file at %s: %v", path, err))
	}
	return string(data)
}
