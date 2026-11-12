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

func TestParseHydroKafkaBrokers(t *testing.T) {
	tests := []struct {
		name        string
		brokers     string
		wantBrokers []string
		wantTLS     bool
		wantErr     bool
		errContains string
	}{
		{
			name:        "single broker without TLS",
			brokers:     "localhost:9092",
			wantBrokers: []string{"localhost:9092"},
			wantTLS:     false,
			wantErr:     false,
		},
		{
			name:        "multiple brokers without TLS",
			brokers:     "broker1:9092,broker2:9092",
			wantBrokers: []string{"broker1:9092", "broker2:9092"},
			wantTLS:     false,
			wantErr:     false,
		},
		{
			name:        "single broker with TLS",
			brokers:     "localhost:9093",
			wantBrokers: []string{"localhost:9093"},
			wantTLS:     true,
			wantErr:     false,
		},
		{
			name:        "multiple brokers with TLS",
			brokers:     "broker1:9093,broker2:9093",
			wantBrokers: []string{"broker1:9093", "broker2:9093"},
			wantTLS:     true,
			wantErr:     false,
		},
		{
			name:        "empty brokers",
			brokers:     "",
			wantBrokers: nil,
			wantTLS:     false,
			wantErr:     true,
			errContains: "HydroKafkaBrokers must be non-empty",
		},
		{
			name:        "mixed ports",
			brokers:     "broker1:9092,broker2:9093",
			wantBrokers: nil,
			wantTLS:     false,
			wantErr:     true,
			errContains: "all Kafka broker addresses must have the same port number",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &Config{
				HydroKafkaBrokers: tt.brokers,
			}

			brokers, enableTLS, err := cfg.ParseHydroKafkaBrokers()

			if tt.wantErr {
				require.Error(t, err)
				if tt.errContains != "" {
					require.Contains(t, err.Error(), tt.errContains)
				}
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.wantBrokers, brokers)
				require.Equal(t, tt.wantTLS, enableTLS)
			}
		})
	}
}

func TestAqueductConfiguredRequiresProdAndFields(t *testing.T) {
	tests := []struct {
		name   string
		cfg    Config
		wantOK bool
	}{
		{
			name:   "disabled by flag",
			cfg:    Config{AqueductEnabled: false, Environment: prodEnv},
			wantOK: false,
		},
		{
			name:   "missing fields",
			cfg:    Config{AqueductEnabled: true, Environment: prodEnv, AqueductURL: ""},
			wantOK: false,
		},
		{
			name:   "production configured",
			cfg:    Config{AqueductEnabled: true, Environment: prodEnv, AqueductURL: "https://example", AqueductAppName: "app", AqueductAPIKey: "key"},
			wantOK: true,
		},
		{
			name:   "proxima configured",
			cfg:    Config{AqueductEnabled: true, Environment: proximaEnv, AqueductURL: "https://example", AqueductAppName: "app", AqueductAPIKey: "key"},
			wantOK: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.wantOK, tt.cfg.AqueductConfigured())
		})
	}
}
