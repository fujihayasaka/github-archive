package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewReference(t *testing.T) {
	ref := []byte("refs/heads/default")
	r := NewReference(ref)
	require.Equal(t, &Reference{Name: ref}, r)
}

func TestReferenceValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		r    *Reference
	}{
		{"empty", NewReference(nil)},
		{"without refs prefix", NewReference([]byte("default"))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Error(t, tt.r.Validate())
		})
	}
}

func TestReferenceValidateFormat(t *testing.T) {
	var tests = []struct {
		name string
		r    *Reference
	}{
		{"with . at start of path component", NewReference([]byte("refs/heads/.bad/name"))},
		{"with .lock at end of path component", NewReference([]byte("refs/heads/bad.lock/name"))},
		{"with ..", NewReference([]byte("refs/tags/v1..0.0"))},
		{"with NUL", NewReference([]byte("refs/heads/bad-0x00\x00-boom"))},
		{"with \\x01", NewReference([]byte("refs/heads/bad-0x01\x01-boom"))},
		{"with \\x02", NewReference([]byte("refs/heads/bad-0x02\x02-boom"))},
		{"with \\x03", NewReference([]byte("refs/heads/bad-0x03\x03-boom"))},
		{"with \\x04", NewReference([]byte("refs/heads/bad-0x04\x04-boom"))},
		{"with \\x05", NewReference([]byte("refs/heads/bad-0x05\x05-boom"))},
		{"with \\x06", NewReference([]byte("refs/heads/bad-0x06\x06-boom"))},
		{"with \\x07", NewReference([]byte("refs/heads/bad-0x07\x07-boom"))},
		{"with \\x08", NewReference([]byte("refs/heads/bad-0x08\x08-boom"))},
		{"with \\x09", NewReference([]byte("refs/heads/bad-0x09\x09-boom"))},
		{"with \\x0a", NewReference([]byte("refs/heads/bad-0x0a\x0a-boom"))},
		{"with \\x0b", NewReference([]byte("refs/heads/bad-0x0b\x0b-boom"))},
		{"with \\x0c", NewReference([]byte("refs/heads/bad-0x0c\x0c-boom"))},
		{"with \\x0d", NewReference([]byte("refs/heads/bad-0x0d\x0d-boom"))},
		{"with \\x0e", NewReference([]byte("refs/heads/bad-0x0e\x0e-boom"))},
		{"with \\x0f", NewReference([]byte("refs/heads/bad-0x0f\x0f-boom"))},
		{"with \\x10", NewReference([]byte("refs/heads/bad-0x10\x10-boom"))},
		{"with \\x11", NewReference([]byte("refs/heads/bad-0x11\x11-boom"))},
		{"with \\x12", NewReference([]byte("refs/heads/bad-0x12\x12-boom"))},
		{"with \\x13", NewReference([]byte("refs/heads/bad-0x13\x13-boom"))},
		{"with \\x14", NewReference([]byte("refs/heads/bad-0x14\x14-boom"))},
		{"with \\x15", NewReference([]byte("refs/heads/bad-0x15\x15-boom"))},
		{"with \\x16", NewReference([]byte("refs/heads/bad-0x16\x16-boom"))},
		{"with \\x17", NewReference([]byte("refs/heads/bad-0x17\x17-boom"))},
		{"with \\x18", NewReference([]byte("refs/heads/bad-0x18\x18-boom"))},
		{"with \\x19", NewReference([]byte("refs/heads/bad-0x19\x19-boom"))},
		{"with \\x1a", NewReference([]byte("refs/heads/bad-0x1a\x1a-boom"))},
		{"with \\x1b", NewReference([]byte("refs/heads/bad-0x1b\x1b-boom"))},
		{"with \\x1c", NewReference([]byte("refs/heads/bad-0x1c\x1c-boom"))},
		{"with \\x1d", NewReference([]byte("refs/heads/bad-0x1d\x1d-boom"))},
		{"with \\x1e", NewReference([]byte("refs/heads/bad-0x1e\x1e-boom"))},
		{"with \\x1f", NewReference([]byte("refs/heads/bad-0x19\x1f-boom"))},
		{"with \\x7f", NewReference([]byte("refs/heads/bad-DEL0177\x7f-boom"))},
		{"with SP", NewReference([]byte("refs/heads/bad-SP -boom"))},
		{"with TILDE", NewReference([]byte("refs/heads/bad-TILDE~-boom"))},
		{"with CARET", NewReference([]byte("refs/heads/bad-CARET^-boom"))},
		{"with COLON", NewReference([]byte("refs/heads/bad-COLON:-boom"))},
		{"with QUESTION", NewReference([]byte("refs/heads/bad-QUESTION?-boom"))},
		{"with STAR", NewReference([]byte("refs/heads/bad-STAR*-boom"))},
		{"with BRACKET", NewReference([]byte("refs/heads/bad-BRACKET[-boom"))},
		{"with / at start", NewReference([]byte("/refs/heads/bad"))},
		{"with double /", NewReference([]byte("refs//heads/bad"))},
		{"with double / in another place", NewReference([]byte("refs/heads//bad"))},
		{"with / at end", NewReference([]byte("refs/heads/bad/"))},
		{"with . at end", NewReference([]byte("refs/heads/bad."))},
		{"with @{", NewReference([]byte("refs/heads/bad-AT-@{-boom"))},
		{"'@'", NewReference([]byte("@"))},
		{"with backslash", NewReference([]byte("refs/heads/bad-BS-\\-boom"))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Errorf(t, tt.r.ValidateFormat(), "with ref = %q", tt.r.GetName())
		})
	}
}

func TestReferenceValidate(t *testing.T) {
	var r *Reference
	require.NoError(t, r.Validate())

	var tests = []struct {
		name string
		r    *Reference
	}{
		{"ref/heads namespace", NewReference([]byte("refs/heads/default"))},
		{"ref/tags namespace", NewReference([]byte("refs/tags/v1.0.0"))},
		{"HEAD symbolic ref", DefaultBranch()},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.r.Validate())
			require.NoError(t, tt.r.ValidateFormat())
		})
	}
}
