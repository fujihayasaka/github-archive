package types

import (
	"github.com/stretchr/testify/require"
	"testing"
)

func TestNewSubmodule(t *testing.T) {
	id := NewObjectID(oid)
	path := NewPath([]byte("path/to/file"))
	sub := NewSubmodule(path, id, "submodule", "/submodule")
	require.Equal(t, sub, &Submodule{
		Path: path,
		Oid:  id,
		Name: "submodule",
		Url:  "/submodule",
	})
}

func TestSubmoduleValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		sub  *Submodule
		err  string
	}{
		{
			"empty",
			&Submodule{},
			"twirp error invalid_argument: submodule.path is required",
		},
		{
			"missing path.name",
			NewSubmodule(NewPath([]byte("")), nil, "", ""),
			"twirp error invalid_argument: path.name is required",
		},
		{
			"missing oid",
			NewSubmodule(NewPath([]byte("path/to/file")), nil, "submodule", "/submodule"),
			"twirp error invalid_argument: submodule.oid is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.sub.Validate(), tt.err)
		})
	}
}
