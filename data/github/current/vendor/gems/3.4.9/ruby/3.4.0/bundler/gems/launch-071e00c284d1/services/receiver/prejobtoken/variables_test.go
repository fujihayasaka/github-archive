package prejobtoken

import (
	"encoding/base64"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

func TestGetEnvironmentVariables_Success(t *testing.T) {
	encodedEnvVariable := base64.StdEncoding.EncodeToString([]byte("variable value"))
	envVariables := map[string]string{
		"env_variable": encodedEnvVariable,
	}

	variablesResponse := &varz.ListVariablesResponse{
		Variables: envVariables,
	}

	varzMockClient := varz.MockClient{}
	varzMockClient.On("ListVariablesForOwner", mock.Anything, mock.Anything, mock.Anything).Return(variablesResponse, nil)

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("env-next-id")

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "variablesAppID").Return(types.GlobalID("variablesAppNextID"), nil)
	variables, err := GetEnvironmentVariables(newTestContext(), &varzMockClient, mockGhTwirpClient, envID, "variablesAppID", observability.NewTestObservability())

	require.NoError(t, err, "Fetching variables should not error")
	assert.NotNil(t, variables, "Variables should not be nil")
	assert.Equal(t, 1, len(variables), "Expected 1 variable in variables map but found %d", 1, len(variables))
	assert.Equal(t, "variable value", variables["env_variable"], "Expected variable \"variable value\" in variables map but found \"%s\"", variables["env_variable"])
}

func TestGetEnvironmentVariables_WithVarzError(t *testing.T) {
	varzMockClient := varz.MockClient{}
	varzMockClient.On("ListVariablesForOwner", mock.Anything, mock.Anything, mock.Anything).Return(&varz.ListVariablesResponse{}, twirp.NotFoundError("variables not found"))

	envID := types.GlobalID(testutils.EncodeGlobalID("Environment", 1234567))
	envNextID := types.GlobalID("env-next-id")

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, envID.String()).Return(envNextID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "variablesAppID").Return(types.GlobalID("variablesAppNextID"), nil)
	variables, err := GetEnvironmentVariables(newTestContext(), &varzMockClient, mockGhTwirpClient, envID, "variablesAppID", observability.NewTestObservability())

	require.Error(t, err, "Fetching variables should error")
	assert.Nil(t, variables, "Variables should be nil")
}
