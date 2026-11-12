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

	frames1 := []*Frame{}
	for frame := range stacks[0].Frames() {
		frames1 = append(frames1, frame)
	}
	require.Greater(t, len(frames1), 0)

	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.TestGetStacks", frames1[0].Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frames1[0].FileName))

	frames2 := []*Frame{}
	for frame := range stacks[1].Frames() {
		frames2 = append(frames2, frame)
	}
	require.Equal(t, len(frames1)+1, len(frames2))

	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.genStackTrace", frames2[0].Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frames2[0].FileName))

	require.Equal(t, "github.com/github/sweagentd/internal/goerrors.TestGetStacks", frames2[1].Function)
	require.Equal(t, "goerrors_test.go", filepath.Base(frames2[1].FileName))
}
