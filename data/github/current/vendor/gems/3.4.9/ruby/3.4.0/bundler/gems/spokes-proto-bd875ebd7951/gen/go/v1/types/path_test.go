package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewPath(t *testing.T) {
	path := []byte("hello\nworld")
	p := NewPath(path)
	require.Equal(t, &Path{Name: path}, p)
}

func TestPathValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		p    *Path
	}{
		{"empty", &Path{}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Error(t, tt.p.Validate())
		})
	}
}

func TestPathValidate(t *testing.T) {
	var p *Path
	require.NoError(t, p.Validate())

	p = NewPath([]byte("README.md"))
	require.NoError(t, p.Validate())
}
