package layouts

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_UnmarshallingError(t *testing.T) {
	r := require.New(t)
	cause := errors.New("proto: unmarshalling failed")
	err := NewUnmarshallingError(cause, "a.type.url")

	r.ErrorIs(err, cause, "UnmarshallingError wraps the causing error")
	r.Equal("layout a.type.url: unmarshalling: proto: unmarshalling failed", err.Error())
}

func Test_TypeError(t *testing.T) {
	r := require.New(t)
	err := NewTypeError("a.type.url")

	r.Equal("layout: a.type.url unrecognized", err.Error())
}
