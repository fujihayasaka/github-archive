package validations

import (
	"testing"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/stretchr/testify/require"
)

func alwaysValid() validator {
	return func() error { return nil }
}

func alwaysInvalid(err error) validator {
	return func() error { return err }
}

func Test_IsValid(t *testing.T) {
	r := require.New(t)

	t.Run("invalid when the validation is empty", func(t *testing.T) {
		v := New()

		r.False(v.IsValid())
		r.ErrorIs(v.ToError(), ErrIsEmpty)
	})

	t.Run("valid when all the validations pass", func(t *testing.T) {
		v := New()
		v.Add(alwaysValid())
		v.Add(alwaysValid())

		r.True(v.IsValid())
		r.NoError(v.ToError())
	})

	t.Run("invalid when one validations fails", func(t *testing.T) {
		v := New()
		err := errors.New("oops")
		v.Add(alwaysValid())
		v.Add(alwaysInvalid(err))

		r.False(v.IsValid())
		r.ErrorIs(v.ToError(), err)
	})
}
