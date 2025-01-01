package test

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Cleanup(t *testing.T, fn func() error) {
	t.Cleanup(func() {
		require.NoError(t, fn())
	})
}
