package validators

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReferenceName(t *testing.T) {
	var tests = []struct {
		name    string
		refname []byte
	}{
		{"with refs prefix", []byte("refs/heads/branch-name")},
		{"with no refs prefix", []byte("my-branch")},
		{"with no refs and multiple components", []byte("my-branch/but/deeper")},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.NoErrorf(t, ReferenceName(tt.refname, "test.refname"), "with ref = %q", tt.refname)
		})
	}
}

func TestReferenceNameError(t *testing.T) {
	var tests = []struct {
		name    string
		refname []byte
	}{
		{"with . at start of path component", []byte("refs/heads/.bad/name")},
		{"with .lock at end of path component", []byte("refs/heads/bad.lock/name")},
		{"with ..", []byte("refs/tags/v1..0.0")},
		{"with NUL", []byte("refs/heads/bad-0x00\x00-boom")},
		{"with \\x01", []byte("refs/heads/bad-0x01\x01-boom")},
		{"with \\x02", []byte("refs/heads/bad-0x02\x02-boom")},
		{"with \\x03", []byte("refs/heads/bad-0x03\x03-boom")},
		{"with \\x04", []byte("refs/heads/bad-0x04\x04-boom")},
		{"with \\x05", []byte("refs/heads/bad-0x05\x05-boom")},
		{"with \\x06", []byte("refs/heads/bad-0x06\x06-boom")},
		{"with \\x07", []byte("refs/heads/bad-0x07\x07-boom")},
		{"with \\x08", []byte("refs/heads/bad-0x08\x08-boom")},
		{"with \\x09", []byte("refs/heads/bad-0x09\x09-boom")},
		{"with \\x0a", []byte("refs/heads/bad-0x0a\x0a-boom")},
		{"with \\x0b", []byte("refs/heads/bad-0x0b\x0b-boom")},
		{"with \\x0c", []byte("refs/heads/bad-0x0c\x0c-boom")},
		{"with \\x0d", []byte("refs/heads/bad-0x0d\x0d-boom")},
		{"with \\x0e", []byte("refs/heads/bad-0x0e\x0e-boom")},
		{"with \\x0f", []byte("refs/heads/bad-0x0f\x0f-boom")},
		{"with \\x10", []byte("refs/heads/bad-0x10\x10-boom")},
		{"with \\x11", []byte("refs/heads/bad-0x11\x11-boom")},
		{"with \\x12", []byte("refs/heads/bad-0x12\x12-boom")},
		{"with \\x13", []byte("refs/heads/bad-0x13\x13-boom")},
		{"with \\x14", []byte("refs/heads/bad-0x14\x14-boom")},
		{"with \\x15", []byte("refs/heads/bad-0x15\x15-boom")},
		{"with \\x16", []byte("refs/heads/bad-0x16\x16-boom")},
		{"with \\x17", []byte("refs/heads/bad-0x17\x17-boom")},
		{"with \\x18", []byte("refs/heads/bad-0x18\x18-boom")},
		{"with \\x19", []byte("refs/heads/bad-0x19\x19-boom")},
		{"with \\x1a", []byte("refs/heads/bad-0x1a\x1a-boom")},
		{"with \\x1b", []byte("refs/heads/bad-0x1b\x1b-boom")},
		{"with \\x1c", []byte("refs/heads/bad-0x1c\x1c-boom")},
		{"with \\x1d", []byte("refs/heads/bad-0x1d\x1d-boom")},
		{"with \\x1e", []byte("refs/heads/bad-0x1e\x1e-boom")},
		{"with \\x1f", []byte("refs/heads/bad-0x19\x1f-boom")},
		{"with \\x7f", []byte("refs/heads/bad-DEL0177\x7f-boom")},
		{"with SP", []byte("refs/heads/bad-SP -boom")},
		{"with TILDE", []byte("refs/heads/bad-TILDE~-boom")},
		{"with CARET", []byte("refs/heads/bad-CARET^-boom")},
		{"with COLON", []byte("refs/heads/bad-COLON:-boom")},
		{"with QUESTION", []byte("refs/heads/bad-QUESTION?-boom")},
		{"with STAR", []byte("refs/heads/bad-STAR*-boom")},
		{"with BRACKET", []byte("refs/heads/bad-BRACKET[-boom")},
		{"with / at start", []byte("/refs/heads/bad")},
		{"with double /", []byte("refs//heads/bad")},
		{"with double / in another place", []byte("refs/heads//bad")},
		{"with / at end", []byte("refs/heads/bad/")},
		{"with . at end", []byte("refs/heads/bad.")},
		{"with @{", []byte("refs/heads/bad-AT-@{-boom")},
		{"with backslash", []byte("refs/heads/bad-BS-\\-boom")},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Errorf(t, ReferenceName(tt.refname, "test.refname"), "with ref = %q", tt.refname)
		})
	}
}
