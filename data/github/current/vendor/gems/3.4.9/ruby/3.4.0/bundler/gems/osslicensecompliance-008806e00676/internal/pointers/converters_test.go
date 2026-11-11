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
