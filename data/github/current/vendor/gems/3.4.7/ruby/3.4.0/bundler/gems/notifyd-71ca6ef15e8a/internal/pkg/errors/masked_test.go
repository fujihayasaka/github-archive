package errors

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Mask(t *testing.T) {
	r := require.New(t)

	t.Run("for an error", func(t *testing.T) {
		mask := "our systems are suffering from excessive load, please retry"
		err := Mask(
			errors.New("mysql error code=9999 everything is broken"),
			mask)

		r.Equal(mask, err.Error(), "should return the mask")
	})

	t.Run("for nil", func(t *testing.T) {
		err := Mask(nil, "some mask")

		r.NoError(err)
	})
}

func Test_Maskf(t *testing.T) {
	r := require.New(t)

	t.Run("for an error", func(t *testing.T) {
		mask := "msg %d"
		err := Maskf(errors.New("inner"), mask, 1)

		r.Equal("msg 1", err.Error(), "should return the formatted mask")
	})

	t.Run("for nil", func(t *testing.T) {
		err := Maskf(nil, "msg %d", 1)

		r.NoError(err)
	})
}

func Test_Unmask(t *testing.T) {
	r := require.New(t)

	t.Run("for a masked error", func(t *testing.T) {
		msg := "mysql error code=9999 everything is broken"
		err := Unmask(
			Mask(errors.New(msg),
				"our systems are suffering from excessive load, please retry"))

		r.Equal(msg, err.Error(), "should return the original error")
	})

	t.Run("for an error masked more than once", func(t *testing.T) {
		msg := "mysql error code=9999 everything is broken"
		innerMasked := Mask(errors.New(msg), "first mask")
		outerMasked := Mask(innerMasked, "second mask")

		err := Unmask(outerMasked)

		r.Equal(msg, err.Error(), "should return the original error")
	})

	t.Run("for an unmasked error", func(t *testing.T) {
		msg := "mysql error code=9999 everything is broken"
		err := Unmask(errors.New(msg))

		r.Equal(msg, err.Error(), "should return the original error")
	})

	t.Run("for nil", func(t *testing.T) {
		r.NoError(Unmask(nil))
	})
}
