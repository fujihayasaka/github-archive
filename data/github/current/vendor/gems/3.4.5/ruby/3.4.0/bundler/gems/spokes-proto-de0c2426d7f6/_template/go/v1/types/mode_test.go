package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewMode(t *testing.T) {
	m := NewMode(exeMode)
	require.Equal(t, &Mode{Mode: exeMode}, m)
}

func TestModeValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		p    *Mode
		err  string
	}{
		{"empty", &Mode{}, "twirp error invalid_argument: mode.mode is required"},
		{"invalid", NewMode(uint32(123)), "twirp error invalid_argument: mode.mode invalid mode"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.p.Validate(), tt.err)
		})
	}
}

func TestModeValidate(t *testing.T) {
	var m *Mode
	require.NoError(t, m.Validate())

	m = NewMode(exeMode)
	require.NoError(t, m.Validate())
}

func TestModeIsDir(t *testing.T) {
	m := NewMode(regMode)
	require.False(t, m.IsDir())

	m = NewMode(dirMode)
	require.True(t, m.IsDir())
}

func TestModeIsRegular(t *testing.T) {
	m := NewMode(dirMode)
	require.False(t, m.IsRegular())

	m = NewMode(regMode)
	require.True(t, m.IsRegular())

	m = NewMode(exeMode)
	require.True(t, m.IsRegular())
}

func TestModeIsSymlink(t *testing.T) {
	m := NewMode(regMode)
	require.False(t, m.IsSymlink())

	m = NewMode(symMode)
	require.True(t, m.IsSymlink())
}

func TestModeIsSubmodule(t *testing.T) {
	m := NewMode(regMode)
	require.False(t, m.IsSubmodule())

	m = NewMode(subMode)
	require.True(t, m.IsSubmodule())
}

func TestModeString(t *testing.T) {
	m := NewMode(regMode)
	require.Equal(t, m.ModeString(), "100644")

	m = NewMode(dirMode)
	require.Equal(t, m.ModeString(), "040000")
}
