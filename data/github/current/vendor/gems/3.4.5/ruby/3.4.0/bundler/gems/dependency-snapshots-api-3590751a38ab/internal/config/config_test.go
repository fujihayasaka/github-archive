package config

import (
	"fmt"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestGetAzureSPNEnvVar(t *testing.T) {
	// production
	cfg := Config{
		Environment:         "production",
		DeployedEnvironment: "production",
	}
	require.Equal(t, cfg.GetAzureSPNEnvVar(), "spn_dependency_snapshots_api")

	// staff-wus2-01
	cfg = Config{
		Environment:         "proxima",
		DeployedEnvironment: "staff-wus2-01",
	}
	require.Equal(t, cfg.GetAzureSPNEnvVar(), "spn_dependency_snapshots_api_staff_wus2_01")

	// prod-weu-01
	cfg = Config{
		Environment:         "proxima",
		DeployedEnvironment: "prod-weu-01",
	}
	require.Equal(t, cfg.GetAzureSPNEnvVar(), "spn_dependency_snapshots_api_prod_weu_01")
}

func TestStackTraceFuncWithNilError(t *testing.T) {
	stackTraceFunc := RootCauseStackTracer
	stack, rollup := stackTraceFunc(nil)

	require.Nil(t, stack)
	require.Empty(t, rollup)
}

func TestStackTraceFuncWithSimpleError(t *testing.T) {
	stackTraceFunc := RootCauseStackTracer
	simpleErr := fmt.Errorf("fmt.Errorf")
	stack, _ := stackTraceFunc(simpleErr)
	require.Len(t, stack, 1)

	frames := stack[0].Frames
	require.True(t, len(frames) >= 4)
	require.Contains(t, frames[len(frames)-4].Function, "TestStackTraceFuncWithSimpleError", "%+v", frames)
	require.Contains(t, frames[len(frames)-3].Function, "RootCauseStackTracer", "%+v", frames)
	require.Contains(t, frames[len(frames)-2].Function, "NewStackTracer", "%+v", frames)
	require.Contains(t, frames[len(frames)-1].Function, "newUnwrappedError", "%+v", frames)
}

func TestStackTraceFuncWithMultiWrappedError(t *testing.T) {
	stackTraceFunc := RootCauseStackTracer
	wrappedErr := nested1(fmt.Errorf("fmt.Errorf"))
	stack, _ := stackTraceFunc(wrappedErr)
	require.Len(t, stack, 1)

	frames := stack[0].Frames
	require.True(t, len(frames) >= 4, "%+v", frames)
	require.Contains(t, frames[len(frames)-4].Function, "TestStackTraceFuncWithMultiWrappedError", "%+v", frames)
	require.Contains(t, frames[len(frames)-3].Function, "nested1", "%+v", frames)
	require.Contains(t, frames[len(frames)-2].Function, "nested2", "%+v", frames)
	require.Contains(t, frames[len(frames)-1].Function, "nested3", "%+v", frames)
}

func TestStackTraceFuncWithSingleWrappedError(t *testing.T) {
	stackTraceFunc := RootCauseStackTracer
	wrappedErr := nestedNoWrap1(fmt.Errorf("fmt.Errorf"))
	stack, _ := stackTraceFunc(wrappedErr)
	require.Len(t, stack, 1)

	frames := stack[0].Frames
	require.True(t, len(frames) >= 4, "%+v", frames)
	require.Contains(t, frames[len(frames)-4].Function, "TestStackTraceFuncWithSingleWrappedError", "%+v", frames)
	require.Contains(t, frames[len(frames)-3].Function, "nestedNoWrap1", "%+v", frames)
	require.Contains(t, frames[len(frames)-2].Function, "nestedNoWrap2", "%+v", frames)
	require.Contains(t, frames[len(frames)-1].Function, "nested3", "%+v", frames)
}

func nested1(err error) error {
	return errors.Wrapf(nested2(err), "hello from nested1")
}

func nested2(err error) error {
	return errors.Wrapf(nested3(err), "hello from nested2")
}

func nested3(err error) error {
	return errors.Wrapf(err, "hello from nested3")
}

func nestedNoWrap1(err error) error {
	return nestedNoWrap2(err)
}

func nestedNoWrap2(err error) error {
	return nested3(err)
}
