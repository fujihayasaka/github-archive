package testutils

import (
	"log"
	"os"
)

// ReadFixture reads the contents of a file at the given path and returns it as a string.
func ReadFixture(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		log.Fatalf("Failed to read fixture file at %s: %v", path, err)
		return ""
	}
	return string(data)
}
