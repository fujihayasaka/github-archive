package exp

import (
	"context"
	"testing"

	gosdk "github.com/github/exp-go-sdk/exp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewClient_Disabled(t *testing.T) {
	client, err := NewClient(ClientConfig{Enabled: false}, log.NewNullLogger())
	require.NoError(t, err)
	assert.NotNil(t, client)
	assert.Nil(t, client.inner, "disabled client should have nil inner")
}

func TestNewClient_EnabledMissingBlobURI(t *testing.T) {
	_, err := NewClient(ClientConfig{Enabled: true, BlobURI: ""}, log.NewNullLogger())
	require.Error(t, err)
	assert.Contains(t, err.Error(), "BlobURI is required")
}

func TestNewClient_SPNMissingAllFields(t *testing.T) {
	_, err := NewClient(ClientConfig{
		Enabled: true,
		BlobURI: "https://example.blob.core.windows.net/container/blob",
	}, log.NewNullLogger())
	require.Error(t, err)
	assert.Contains(t, err.Error(), "missing required Azure credential fields")
}

func TestNewClient_SPNMissingSingleField(t *testing.T) {
	tests := []struct {
		name string
		cfg  ClientConfig
	}{
		{
			name: "missing TenantID",
			cfg: ClientConfig{
				Enabled:  true,
				BlobURI:  "https://example.blob.core.windows.net/container/blob",
				ClientID: "cid",
			},
		},
		{
			name: "missing ClientID",
			cfg: ClientConfig{
				Enabled:  true,
				BlobURI:  "https://example.blob.core.windows.net/container/blob",
				TenantID: "tid",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewClient(tt.cfg, log.NewNullLogger())
			require.Error(t, err)
		})
	}
}

func TestNewClient_WithSourceBypassesSPN(t *testing.T) {
	source := gosdk.NewInMemorySource([]byte{})
	client, err := NewClient(ClientConfig{Enabled: true}, log.NewNullLogger(), WithSource(source))
	require.NoError(t, err)
	assert.NotNil(t, client.inner)
}

func TestNewClient_WithScopes(t *testing.T) {
	source := gosdk.NewInMemorySource([]byte{})
	scopes := []string{"scope-a", "scope-b"}
	client, err := NewClient(ClientConfig{Enabled: true}, log.NewNullLogger(),
		WithSource(source), WithScopes(scopes))
	require.NoError(t, err)
	assert.Equal(t, scopes, client.scopes)
}

func TestNewClient_WithStatsClient(t *testing.T) {
	source := gosdk.NewInMemorySource([]byte{})
	statter := stats.NullStatter
	client, err := NewClient(ClientConfig{Enabled: true}, log.NewNullLogger(),
		WithSource(source), WithStatsClient(statter))
	require.NoError(t, err)
	assert.Equal(t, statter, client.statter)
}

func TestClient_ResilientStart_Noop(t *testing.T) {
	client := NewNoopClient()
	err := client.ResilientStart(context.Background())
	assert.NoError(t, err)
}

func TestClient_GetAssignment_Noop(t *testing.T) {
	client := NewNoopClient()
	result := client.GetAssignment(context.Background(), map[string]string{"user": "test"}, nil, nil)
	assert.NotNil(t, result)
}

func TestClient_GetAssignment_EmptyParams(t *testing.T) {
	source := gosdk.NewInMemorySource([]byte{})
	client, err := NewClient(ClientConfig{Enabled: true}, log.NewNullLogger(),
		WithSource(source))
	require.NoError(t, err)

	result := client.GetAssignment(context.Background(), nil, nil, nil)
	assert.NotNil(t, result, "should return noop result for empty params")
}

func TestClient_GetAssignment_EmptyParamsIncrementsStat(t *testing.T) {
	var capturedKey string
	var capturedTags stats.Tags
	mockStatter := &incrementCapture{
		onIncrement: func(key string, tags stats.Tags) {
			capturedKey = key
			capturedTags = tags
		},
	}

	source := gosdk.NewInMemorySource([]byte{})
	client, err := NewClient(ClientConfig{Enabled: true}, log.NewNullLogger(),
		WithSource(source), WithStatsClient(mockStatter))
	require.NoError(t, err)

	client.GetAssignment(context.Background(), nil, nil, nil)
	assert.Equal(t, "exp.assignment.request", capturedKey)
	assert.Equal(t, "no_params", capturedTags["result"])
}

// incrementCapture is a test helper that captures Increment calls.
type incrementCapture struct {
	stats.NullClient

	onIncrement func(key string, tags stats.Tags)
}

func (c *incrementCapture) Increment(key string, tags stats.Tags) {
	if c.onIncrement != nil {
		c.onIncrement(key, tags)
	}
}

func TestNewNoopClient(t *testing.T) {
	client := NewNoopClient()
	assert.NotNil(t, client)
	assert.Nil(t, client.inner)
	assert.Nil(t, client.scopes)
	assert.Nil(t, client.statter)
}

func TestRedactBlobURI(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"full URI with SAS token", "https://blob.core.windows.net/container/blob?sv=2021-06-08&sig=secret", "blob.core.windows.net/container/blob"},
		{"URI without query", "https://blob.core.windows.net/container/blob", "blob.core.windows.net/container/blob"},
		{"invalid URI", "://bad", "[invalid-uri]"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, redactBlobURI(tt.input))
		})
	}
}

// --- NewClientFromConfig tests ---

func TestNewClientFromConfig_ProximaReturnsNoop(t *testing.T) {
	cfg := &config.Config{
		Environment:               config.EnvironmentProxima,
		ExperimentationSDKBlobURI: "https://blob.core.windows.net/container/blob",
	}
	obsv := observability.NewNoopExporters()

	client, err := NewClientFromConfig(context.Background(), cfg, obsv)
	require.NoError(t, err)
	assert.NotNil(t, client)

	// Verify it's a noop by checking GetAssignment returns a default result
	result := client.GetAssignment(context.Background(), map[string]string{"user": "u"}, nil, nil)
	assert.NotNil(t, result)
}

func TestNewClientFromConfig_EmptyBlobURIReturnsNoop(t *testing.T) {
	cfg := &config.Config{
		Environment:               config.EnvironmentDevelopment,
		ExperimentationSDKBlobURI: "",
	}
	obsv := observability.NewNoopExporters()

	client, err := NewClientFromConfig(context.Background(), cfg, obsv)
	require.NoError(t, err)
	assert.NotNil(t, client)
}

func TestNewClientFromConfig_MissingSPNFallsBackToNoop(t *testing.T) {
	cfg := &config.Config{
		Environment:               config.EnvironmentStaging,
		ExperimentationSDKBlobURI: "https://blob.core.windows.net/container/blob",
		// SPN credentials intentionally left empty
	}
	obsv := observability.NewNoopExporters()

	client, err := NewClientFromConfig(context.Background(), cfg, obsv)
	require.NoError(t, err, "should not return error, should fall back to noop")
	assert.NotNil(t, client)

	// Verify it behaves as noop
	result := client.GetAssignment(context.Background(), map[string]string{"user": "u"}, nil, nil)
	assert.NotNil(t, result)
}

func TestNewClientFromConfig_PartialSPNFallsBackToNoop(t *testing.T) {
	tests := []struct {
		name     string
		tenantID string
		clientID string
	}{
		{"only TenantID", "tid", ""},
		{"only ClientID", "", "cid"},
		{"both missing", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &config.Config{
				Environment:                config.EnvironmentStaging,
				ExperimentationSDKBlobURI:  "https://blob.core.windows.net/container/blob",
				ExperimentationSPNTenantID: tt.tenantID,
				ExperimentationSPNClientID: tt.clientID,
			}
			obsv := observability.NewNoopExporters()

			client, err := NewClientFromConfig(context.Background(), cfg, obsv)
			require.NoError(t, err, "should fall back to noop, not error")
			assert.NotNil(t, client)
		})
	}
}

func TestNewClientFromConfig_DevelopmentEnvUsesAzureCLICred(t *testing.T) {
	// In development mode, the client tries to use Azure CLI credentials.
	// Without Azure CLI configured, this will fail and fall back to noop.
	cfg := &config.Config{
		Environment:               config.EnvironmentDevelopment,
		ExperimentationSDKBlobURI: "https://blob.core.windows.net/container/blob",
	}
	obsv := observability.NewNoopExporters()

	client, err := NewClientFromConfig(context.Background(), cfg, obsv)
	require.NoError(t, err, "should fall back to noop on Azure CLI cred failure")
	assert.NotNil(t, client)
}

func TestNewAssignmentResult(t *testing.T) {
	vars := map[string]string{"flag": "treatment"}
	result := NewAssignmentResult(vars, "ctx-123", 42)
	assert.NotNil(t, result)
}
