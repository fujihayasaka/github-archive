package goerrors

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func genStackTrace(err error) error {
	return WithStack(err)
}

func TestGetStacks(t *testing.T) {
	// Create first error with stack trace
	err := errors.New("first error")
	errWithStack1 := genStackTrace(err)

	// Create second error with stack trace, wrapping the first
	errWithStack2 := WithStack(errWithStack1)

	// Get all stacks
	stacks := GetStacks(errWithStack2)

	// Verify we got two stack traces
	require.Len(t, stacks, 2)

	// Verify both stacks have frames
	require.NotNil(t, stacks[0])
	require.NotNil(t, stacks[1])

	// Verify we can get frames from each stack
	frames1 := stacks[0].Frames()
	require.NotNil(t, frames1)

	frame, _ := frames1.Next()
	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.TestGetStacks", frame.Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frame.File))

	frames2 := stacks[1].Frames()
	require.NotNil(t, frames2)

	frame, more := frames2.Next()
	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.genStackTrace", frame.Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frame.File))
	require.True(t, more)

	frame, _ = frames2.Next()
	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.TestGetStacks", frame.Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frame.File))
}
