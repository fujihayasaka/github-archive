package azureauth_test

import (
	"testing"

	"github.com/github/sweagentd/internal/azureauth"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewAzureCredential_MissingFields(t *testing.T) {
	_, err := azureauth.NewAzureCredential("", "")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "tenantID")
	assert.Contains(t, err.Error(), "clientID")
}

func TestNewAzureCredential_MissingTenantID(t *testing.T) {
	_, err := azureauth.NewAzureCredential("", "client-id")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "tenantID")
	assert.NotContains(t, err.Error(), "clientID")
}

func TestNewAzureCredential_MissingClientID(t *testing.T) {
	_, err := azureauth.NewAzureCredential("tenant-id", "")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "clientID")
	assert.NotContains(t, err.Error(), "tenantID")
}
