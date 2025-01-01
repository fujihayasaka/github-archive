package utils

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// AssertNormalizedEqual asserts that two strings are equal after normalizing
// line endings, providing stable tests across platforms.
func AssertNormalizedEqual(t *testing.T, expected, actual string, msgAndArgs ...interface{}) {
	t.Helper()
	normalizedExpected := NormalizeLineEndings(expected)
	normalizedActual := NormalizeLineEndings(actual)
	assert.Equal(t, normalizedExpected, normalizedActual, msgAndArgs...)
}
