// Package utils contains various utility functions
package utils

import (
	"encoding/binary"
	"fmt"
	"hash/fnv"
)

// HashEmail hashes an email to a hex string, first normalizing it
func HashEmail(s string) (string, error) {
	return hashString(NormalizeEmail(s))
}

// HashUint64 hashes a uint64 to a hex string
func HashUint64(n uint64) (string, error) {
	buf := make([]byte, 8)
	binary.LittleEndian.PutUint64(buf, n)
	return hashBytes(buf)
}

// hashString hashes a string to a hex string
func hashString(s string) (string, error) {
	return hashBytes([]byte(s))
}

// hashBytes hashes a byte slice to a hex string
func hashBytes(b []byte) (string, error) {
	h := fnv.New64a()
	if _, err := h.Write(b); err != nil {
		return "", fmt.Errorf("failed to write hash: %w", err)
	}
	return fmt.Sprintf("%x", h.Sum64()), nil
}
