package fromctx_test

import (
	"testing"

	"github.com/github/turboghas/internal/fromctx"
	"github.com/stretchr/testify/require"
)

func TestEnterprise(t *testing.T) {
	require.True(t, fromctx.Environment("enterprise").IsEnterprise())
	require.False(t, fromctx.Environment("development").IsEnterprise())
}

func TestDevelopment(t *testing.T) {
	require.False(t, fromctx.Environment("enterprise").IsDevelopment())
	require.True(t, fromctx.Environment("development").IsDevelopment())
}

func TestIsTest(t *testing.T) {
	require.True(t, fromctx.IsTest)
}
