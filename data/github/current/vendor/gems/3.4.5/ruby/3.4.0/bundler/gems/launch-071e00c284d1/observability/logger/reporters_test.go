package logger

import (
	goerrors "errors"
	"fmt"
	"os"
	"runtime"
	"strings"
	"testing"

	"github.com/github/go-exceptions"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability/kvperrors"
)

func TestStackTraceFn(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	msg := "test pkg/errors"
	err = errors.New(msg)
	trace, rollup := stacktraceFn(err)

	st1 := trace[0]
	assert.Equal(t, "*errors.fundamental", st1.Type)
	assert.Equal(t, msg, st1.Value)
	assert.Len(t, st1.Frames, 3)

	assertFrame(t, frameZero(), st1.Frames[0])

	assertFrame(t, frameOne(), st1.Frames[1])

	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters_test.go",
		AbsPath:    fmt.Sprintf("%s/reporters_test.go", wd),
		LineNumber: "24",
		Function:   "TestStackTraceFn",
	}, st1.Frames[2])

	expectedRollup := fmt.Sprintf(
		"%s:github.com/github/launch/observability/logger.TestStackTraceFn\n\t%s/reporters_test.go:24",
		msg, wd,
	)
	assert.Equal(t, expectedRollup, rollup)
}

func TestStackTraceFn_WrappedErr(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	sourceErr := goerrors.New("This is a go error")
	wrappedErr := errors.Wrap(sourceErr, "This is the wrapper")

	trace, rollup := stacktraceFn(wrappedErr)

	st1 := trace[0]
	assert.Equal(t, "*errors.errorString", st1.Type)
	assert.Equal(t, "This is the wrapper: This is a go error", st1.Value)
	require.Len(t, st1.Frames, 3)

	// Third frame is the the error we care about
	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters_test.go",
		AbsPath:    fmt.Sprintf("%s/observability/logger/reporters_test.go", strings.TrimSuffix(wd, "/observability/logger")),
		LineNumber: "29",
		Function:   "TestStackTraceFn_WrappedErr",
	}, st1.Frames[2])

	// We don't want to see the errs.Wrap here in the rollup
	expectedRollup := fmt.Sprintf(
		"This is the wrapper: This is a go error:github.com/github/launch/observability/logger.TestStackTraceFn_WrappedErr\n\t%s/reporters_test.go:55",
		wd,
	)
	assert.Equal(t, expectedRollup, rollup)
}

func TestStackTraceFn_GoErr(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	// Even a bare error should get wrapped and a stacktrace
	goErr := goerrors.New("This is a go error")

	trace, rollup := stacktraceFn(goErr)

	st1 := trace[0]
	assert.Equal(t, "*errors.errorString", st1.Type)
	assert.Equal(t, "Unwrapped error: This is a go error", st1.Value)
	assert.Len(t, st1.Frames, 5)

	// Third frame is the where we are calling from, inside this test function
	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters_test.go",
		AbsPath:    fmt.Sprintf("%s/reporters_test.go", wd),
		LineNumber: "87",
		Function:   "TestStackTraceFn_GoErr",
	}, st1.Frames[2])

	// Fourth frame is in the stacktraceFn where it creates the newUnwrappedError
	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters.go",
		AbsPath:    fmt.Sprintf("%s/reporters.go", wd),
		LineNumber: "68",
		Function:   "stacktraceFn",
	}, st1.Frames[3])

	// Fifth frame is newUnwrappedError
	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters.go",
		AbsPath:    fmt.Sprintf("%s/reporters.go", wd),
		LineNumber: "141",
		Function:   "newUnwrappedError",
	}, st1.Frames[4])

	// We don't want of these errors to have the same rollup so we implemented Rollup on it
	assert.Equal(t, "Unwrapped error: This is a go error", rollup)
}

func TestStackTraceFn_KvpErrors(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	err = kvperrors.New("test kvperrors")
	trace, rollup := stacktraceFn(err)

	st1 := trace[0]
	assert.Equal(t, "*errors.fundamental", st1.Type)
	assert.Equal(t, "test kvperrors", st1.Value)
	require.Len(t, st1.Frames, 4)

	assertFrame(t, frameZero(), st1.Frames[0])
	assertFrame(t, frameOne(), st1.Frames[1])

	assertFrame(t, exceptions.StackFrame{
		FileName:   "reporters_test.go",
		AbsPath:    fmt.Sprintf("%s/reporters_test.go", wd),
		LineNumber: "126",
		Function:   "TestStackTraceFn_KvpErrors",
	}, st1.Frames[2])

	assertFrame(t, exceptions.StackFrame{
		FileName:   "kvperrors.go",
		AbsPath:    fmt.Sprintf("%s/observability/kvperrors/kvperrors.go", strings.TrimSuffix(wd, "/observability/logger")),
		LineNumber: "12",
		Function:   "New",
	}, st1.Frames[3])

	expectedRollup := fmt.Sprintf(
		"test kvperrors:github.com/github/launch/observability/logger.TestStackTraceFn_KvpErrors\n\t%s/reporters_test.go:126",
		wd,
	)
	assert.Equal(t, expectedRollup, rollup)
}

type customErr struct {
	err        error
	rollup     string
	stackTrace errors.StackTrace
}

func (e *customErr) Error() string {
	return e.err.Error()
}

func (e *customErr) Rollup(backtrace errors.StackTrace) string {
	return e.rollup
}

func (e *customErr) StackTrace() errors.StackTrace {
	return e.stackTrace
}

func TestStackTraceFn_CustomRollup(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	e := errors.New("test pkg/errors")
	type stackTracer interface {
		StackTrace() errors.StackTrace
	}
	err = &customErr{e, "test", e.(stackTracer).StackTrace()}

	_, rollup := stacktraceFn(err)
	assert.Equal(t, "test", rollup)

	err = &customErr{e, "", e.(stackTracer).StackTrace()}
	expectedRollup := fmt.Sprintf(
		"test pkg/errors:github.com/github/launch/observability/logger.TestStackTraceFn_CustomRollup\n\t%s/reporters_test.go:180",
		wd,
	)
	_, rollup = stacktraceFn(err)
	assert.Equal(t, expectedRollup, rollup)
}

func frameZero() exceptions.StackFrame {
	return exceptions.StackFrame{
		FileName:   fmt.Sprintf("asm_%s.s", runtime.GOARCH),
		AbsPath:    fmt.Sprintf("%s/src/runtime/asm_%s.s", runtime.GOROOT(), runtime.GOARCH),
		LineNumber: "1373",
		Function:   "goexit",
	}
}

func frameOne() exceptions.StackFrame {
	return exceptions.StackFrame{
		FileName:   "testing.go",
		AbsPath:    fmt.Sprintf("%s/src/testing/testing.go", runtime.GOROOT()),
		LineNumber: "992",
		Function:   "tRunner",
	}
}

// asserts frames are equal barring the LineNumber property
func assertFrame(t assert.TestingT, expected exceptions.StackFrame, actual exceptions.StackFrame) {
	assert.Equal(t, expected.FileName, actual.FileName)
	assert.Equal(t, expected.AbsPath, actual.AbsPath)
	assert.Equal(t, expected.Function, actual.Function)
}
