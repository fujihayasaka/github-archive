package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewRepository(t *testing.T) {
	r := NewRepository(1)
	require.Equal(t, &Repository{Type: Repository_TYPE_REPOSITORY, Id: 1}, r)
}

func TestNewWiki(t *testing.T) {
	r := NewWiki(1)
	require.Equal(t, &Repository{Type: Repository_TYPE_WIKI, Id: 1}, r)
}

func TestNewGist(t *testing.T) {
	r := NewGist(1)
	require.Equal(t, &Repository{Type: Repository_TYPE_GIST, Id: 1}, r)
}

func TestRepositoryValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		r    *Repository
	}{
		{"empty", &Repository{}},
		{"invalid type", &Repository{Type: 123, Id: 1}},
		{"missing id", &Repository{Type: Repository_TYPE_REPOSITORY}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Error(t, tt.r.Validate())
		})
	}
}

func TestRepositoryValidate(t *testing.T) {
	var r *Repository
	require.NoError(t, r.Validate())
}
