package utils

import (
	"bytes"
	"strings"
)

func UnescapeConsulKVString(s string) string {
	return strings.ReplaceAll(s, "\\n", "\n")
}

func UnescapeConsulKVBytes(b []byte) []byte {
	return bytes.ReplaceAll(b, []byte("\\n"), []byte("\n"))
}
