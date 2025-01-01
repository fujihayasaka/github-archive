package prejobtoken

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild"
)

func TestGetEnvironmentSecrets(t *testing.T) {
	envSecrets := map[string]string{
		"my_secret": "hello env",
	}

	secretsResponse := &kredz.ListSecretsResponse{
		Secrets: envSecrets,
	}

	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForOwner", mock.Anything, mock.Anything, mock.Anything).Return(secretsResponse, nil)

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("env-next-id")

	mockDecryptor := &earthsmoke.MockDecryptor{}
	mockDecryptor.On("DecryptSecretValue", mock.Anything, envSecrets["my_secret"], envNextID.String(), workflowbuild.ActionsSecretSource).Return(envSecrets["my_secret"], true, nil)

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)
	secrets, err := GetEnvironmentSecrets(newTestContext(), &credzMockClient, mockGhTwirpClient, mockDecryptor, envID, "secretsAppID", observability.NewTestObservability())

	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secrets, "Secrets should not be nil")
	assert.Equal(t, 1, len(secrets), "Expected 1 secret in secrets map but found %d", 1, len(secrets))
	assert.Equal(t, "hello env", secrets["my_secret"], "Expected secret \"hello env\" in secrets map but found \"%s\"", secrets["my_secret"])
}

func newTestContext() context.Context {
	return context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
}
