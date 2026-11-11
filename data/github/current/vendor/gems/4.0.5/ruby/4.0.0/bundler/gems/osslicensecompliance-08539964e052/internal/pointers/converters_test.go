package pointers_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/stretchr/testify/require"
)

func TestValueOrZero_Int(t *testing.T) {
	var ni *int
	require.Equal(t, 0, pointers.ValueOrZero(ni))
	v := 42
	require.Equal(t, 42, pointers.ValueOrZero(&v))
}

func TestValueOrZero_String(t *testing.T) {
	var ns *string
	require.Equal(t, "", pointers.ValueOrZero(ns))
	s := "hello"
	require.Equal(t, "hello", pointers.ValueOrZero(&s))
}

func TestValueOrZero_Bool(t *testing.T) {
	var nb *bool
	require.Equal(t, false, pointers.ValueOrZero(nb))
	b := true
	require.Equal(t, true, pointers.ValueOrZero(&b))
}

func TestValueOrZero_Struct(t *testing.T) {
	type S struct {
		A int
		B string
	}
	var ns *S
	require.Equal(t, S{}, pointers.ValueOrZero(ns))
	val := S{A: 7, B: "x"}
	require.Equal(t, val, pointers.ValueOrZero(&val))
}

func TestZeroToNil_Uint64(t *testing.T) {
	require.Nil(t, pointers.ZeroToNil(uint64(0)))

	result := pointers.ZeroToNil(uint64(42))
	require.NotNil(t, result)
	require.Equal(t, uint64(42), *result)
}

func TestZeroToNil_String(t *testing.T) {
	require.Nil(t, pointers.ZeroToNil(""))

	result := pointers.ZeroToNil("hello")
	require.NotNil(t, result)
	require.Equal(t, "hello", *result)
}

func TestZeroToNil_Int(t *testing.T) {
	require.Nil(t, pointers.ZeroToNil(0))

	result := pointers.ZeroToNil(42)
	require.NotNil(t, result)
	require.Equal(t, 42, *result)
}

func TestZeroToNil_Bool(t *testing.T) {
	require.Nil(t, pointers.ZeroToNil(false))

	result := pointers.ZeroToNil(true)
	require.NotNil(t, result)
	require.Equal(t, true, *result)
}
