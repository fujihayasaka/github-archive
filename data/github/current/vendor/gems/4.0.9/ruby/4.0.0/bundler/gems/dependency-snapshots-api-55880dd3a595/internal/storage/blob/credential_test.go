package blob

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetAzureCredential_FallsBackToClientSecret(t *testing.T) {
	// When OIDC env vars are not set but SPN credentials are available,
	// getAzureCredential should fall back to client secret authentication.
	t.Setenv("AZURE_FEDERATED_TOKEN_FILE", "")
	t.Setenv("AZURE_CLIENT_ID", "")
	t.Setenv("AZURE_TENANT_ID", "")

	// Set up SPN credentials via the config's expected env vars
	t.Setenv("spn_dependency_snapshots_api", "fake-secret-key")
	t.Setenv("spn_dependency_snapshots_api_client_id", "fake-client-id")
	t.Setenv("spn_dependency_snapshots_api_tenant_id", "fake-tenant-id")

	cfg, err := config.Load("test")
	require.NoError(t, err)

	ctx := context.Background()
	cred, err := getAzureCredential(ctx, cfg)
	require.NoError(t, err)
	assert.NotNil(t, cred, "should return a client secret credential when OIDC is not available")
}

func TestGetAzureCredential_FailsWhenNeitherAvailable(t *testing.T) {
	// When neither OIDC nor SPN credentials are present, getAzureCredential should error.
	t.Setenv("AZURE_FEDERATED_TOKEN_FILE", "")
	t.Setenv("AZURE_CLIENT_ID", "")
	t.Setenv("AZURE_TENANT_ID", "")
	t.Setenv("spn_dependency_snapshots_api", "")
	t.Setenv("spn_dependency_snapshots_api_client_id", "")
	t.Setenv("spn_dependency_snapshots_api_tenant_id", "")

	cfg, err := config.Load("test")
	require.NoError(t, err)

	ctx := context.Background()
	cred, err := getAzureCredential(ctx, cfg)
	assert.Error(t, err, "should fail when no credentials are available")
	assert.Nil(t, cred)
	assert.Contains(t, err.Error(), "Workload Identity not configured")
	assert.Contains(t, err.Error(), "SPN client secret credentials not found")
}

func TestInitializeBlobClientIfEnabled_DevModeWhenNoCredentials(t *testing.T) {
	// With no OIDC or SPN credentials and non-enterprise config, should fall back to dev mode.
	// Dev mode connects to Azurite; if Azurite isn't running we accept a connection error.
	t.Setenv("AZURE_FEDERATED_TOKEN_FILE", "")
	t.Setenv("AZURE_CLIENT_ID", "")
	t.Setenv("AZURE_TENANT_ID", "")
	t.Setenv("spn_dependency_snapshots_api", "")
	t.Setenv("spn_dependency_snapshots_api_client_id", "")
	t.Setenv("spn_dependency_snapshots_api_tenant_id", "")

	cfg, err := config.Load("test")
	require.NoError(t, err)
	cfg.Enterprise = false

	ctx := context.Background()
	client, err := initializeBlobClientIfEnabled(ctx, cfg, "test-container")
	// This may fail if Azurite isn't running — that's fine, the important thing
	// is that it attempts dev mode, not authenticated mode.
	if err != nil {
		assert.NotContains(t, err.Error(), "Workload Identity",
			"error should be about connecting to dev storage, not about credentials")
		assert.NotContains(t, err.Error(), "client secret",
			"error should be about connecting to dev storage, not about credentials")
	} else {
		assert.NotNil(t, client)
	}
}

func TestInitializeBlobClientIfEnabled_EnterpriseReturnsNil(t *testing.T) {
	cfg, err := config.Load("test")
	require.NoError(t, err)
	cfg.Enterprise = true

	ctx := context.Background()
	client, err := initializeBlobClientIfEnabled(ctx, cfg, "test-container")
	assert.NoError(t, err)
	assert.Nil(t, client, "enterprise mode should not initialize blob client")
}

func TestGetAzureCredential_OIDCFallsBackWhenTokenFails(t *testing.T) {
	// When OIDC env vars are set but the token exchange fails (e.g., trust not
	// configured), getAzureCredential should fall back to client secret.
	t.Setenv("AZURE_FEDERATED_TOKEN_FILE", "/fake/token/path")
	t.Setenv("AZURE_CLIENT_ID", "fake-client-id")
	t.Setenv("AZURE_TENANT_ID", "fake-tenant-id")

	// SPN credentials available as fallback
	t.Setenv("spn_dependency_snapshots_api", "fake-secret-key")
	t.Setenv("spn_dependency_snapshots_api_client_id", "fake-client-id")
	t.Setenv("spn_dependency_snapshots_api_tenant_id", "fake-tenant-id")

	cfg, err := config.Load("test")
	require.NoError(t, err)

	ctx := context.Background()
	cred, err := getAzureCredential(ctx, cfg)
	// OIDC token exchange will fail (no real trust configured), but it should
	// fall back to client secret successfully.
	require.NoError(t, err)
	assert.NotNil(t, cred, "should fall back to client secret when OIDC token exchange fails")
}

func TestGetAzureCredential_OIDCFailsWithoutSPNFallback(t *testing.T) {
	// When OIDC env vars are set, token exchange fails, and no SPN is available,
	// getAzureCredential should return an error.
	t.Setenv("AZURE_FEDERATED_TOKEN_FILE", "/fake/token/path")
	t.Setenv("AZURE_CLIENT_ID", "fake-client-id")
	t.Setenv("AZURE_TENANT_ID", "fake-tenant-id")

	// No SPN credentials
	t.Setenv("spn_dependency_snapshots_api", "")
	t.Setenv("spn_dependency_snapshots_api_client_id", "")
	t.Setenv("spn_dependency_snapshots_api_tenant_id", "")

	cfg, err := config.Load("test")
	require.NoError(t, err)

	ctx := context.Background()
	cred, err := getAzureCredential(ctx, cfg)
	assert.Error(t, err)
	assert.Nil(t, cred)
	assert.Contains(t, err.Error(), "SPN client secret credentials not found")
}

func TestIsOIDCConfigured(t *testing.T) {
	tests := []struct {
		name      string
		tokenFile string
		clientID  string
		tenantID  string
		expected  bool
	}{
		{"all set", "/var/run/secrets/azure/tokens/azure-identity-token", "client-id", "tenant-id", true},
		{"none set", "", "", "", false},
		{"only token file", "/var/run/secrets/azure/tokens/azure-identity-token", "", "", false},
		{"missing token file", "", "client-id", "tenant-id", false},
		{"missing client id", "/var/run/secrets/azure/tokens/azure-identity-token", "", "tenant-id", false},
		{"missing tenant id", "/var/run/secrets/azure/tokens/azure-identity-token", "client-id", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("AZURE_FEDERATED_TOKEN_FILE", tt.tokenFile)
			t.Setenv("AZURE_CLIENT_ID", tt.clientID)
			t.Setenv("AZURE_TENANT_ID", tt.tenantID)
			assert.Equal(t, tt.expected, isOIDCConfigured())
		})
	}
}
