package workflowinvoker

import (
	"context"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowbuild/build"
)

func TestSecretsReplacesOrgSecretsWithRepoSecrets(t *testing.T) {
	repositorySecrets := map[string]string{
		"my_secret": "hello repo",
	}

	organizationSecrets := map[string]string{
		"my_secret": "hello_organization",
	}
	secretsForRepository := &kredz.RepositorySecretsResponse{
		RepositorySecrets:   repositorySecrets,
		OrganizationSecrets: organizationSecrets,
	}
	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "team",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.ActionsSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secretStore, "Secrets should not be nil")

	secret := secretStore.GetEncryptedSecrets()["my_secret"]
	expectedValue := "hello repo"
	assert.Equal(t, 1, len(secretStore.GetEncryptedSecrets()), "Expected %d secrets in secrets map but found %d", 1, len(secretStore.GetEncryptedSecrets()))
	assert.Equal(t, expectedValue, secret.Value, "Expected secret \"%s\" in secrets map but found \"%s\"", expectedValue, secret.Value)
	assert.Equal(t, repoID.String(), secret.Scope, "Expected secret to have scope \"%s\" in secrets map but found \"%s\"", repoID.String(), secret.Scope)
}

func TestSecretsIncludesOrgSecrets(t *testing.T) {
	organizationSecrets := map[string]string{
		"my_secret": "hello organization",
	}
	secretsForRepository := &kredz.RepositorySecretsResponse{
		OrganizationSecrets: organizationSecrets,
	}
	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.ActionsSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secretStore, "Secrets should not be nil")

	secret := secretStore.GetEncryptedSecrets()["my_secret"]
	expectedValue := "hello organization"
	assert.Equal(t, 1, len(secretStore.GetEncryptedSecrets()), "Expected %d secrets in secrets map but found %d", 1, len(secretStore.GetEncryptedSecrets()))
	assert.Equal(t, expectedValue, secret.Value, "Expected secret \"%s\" in secrets map but found \"%s\"", expectedValue, secret.Value)
	assert.Equal(t, orgID.String(), secret.Scope, "Expected secret to have scope \"%s\" in secrets map but found \"%s\"", orgID.String(), secret.Scope)
}

func TestSecretsIgnoresOrgSecretsForUsers(t *testing.T) {
	ownerSecrets := map[string]string{
		"my_secret": "hello user",
	}

	secretsForRepository := &kredz.RepositorySecretsResponse{
		OrganizationSecrets: ownerSecrets,
	}
	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "User",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "pro",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, ownerID.String()).Return(ownerID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.ActionsSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secretStore, "Secrets should not be nil")
	assert.Equal(t, 0, len(secretStore.GetEncryptedSecrets()), "Expected %d secrets in secrets map but found %d", 0, len(secretStore.GetEncryptedSecrets()))
}

func TestSecretsIgnoresOrgSecretsForAdvisoryWorkspaces(t *testing.T) {
	ownerSecrets := map[string]string{
		"my_secret": "hello advisory workspace",
	}

	secretsForRepository := &kredz.RepositorySecretsResponse{
		OrganizationSecrets: ownerSecrets,
	}
	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsAdvisoryWorkspace: true,
		RepoIsPrivate:           false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "pro",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, ownerID.String()).Return(ownerID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.ActionsSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secretStore, "Secrets should not be nil")
	assert.Equal(t, 0, len(secretStore.GetEncryptedSecrets()), "Expected %d secrets in secrets map but found %d", 0, len(secretStore.GetEncryptedSecrets()))
}

func TestSecretsIgnoresOrgSecretsForFreeOrgs(t *testing.T) {

	repositorySecrets := map[string]string{
		"my_secret": "hello repo",
	}

	organizationSecrets := map[string]string{
		"my_org_secret": "hello organization",
	}
	secretsForRepository := &kredz.RepositorySecretsResponse{
		RepositorySecrets:   repositorySecrets,
		OrganizationSecrets: organizationSecrets,
	}

	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: true,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "free_organization",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, ownerID.String()).Return(ownerID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.ActionsSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	assert.NotNil(t, secretStore, "Secrets should not be nil")

	encryptedSecret := secretStore.GetEncryptedSecrets()["my_secret"]
	expectedValue := "hello repo"
	assert.Equal(t, 1, len(secretStore.GetEncryptedSecrets()), "Expected %d secrets in secrets map but found %d", 1, len(secretStore.GetEncryptedSecrets()))
	assert.Equal(t, expectedValue, encryptedSecret.Value, "Expected secret \"%s\" in secrets map but found \"%s\"", expectedValue, expectedValue)
	assert.Equal(t, repoID.String(), encryptedSecret.Scope, "Expected secret to have scope \"%s\" in secrets map but found \"%s\"", repoID.String(), encryptedSecret.Scope)
}

func TestSecretsAllowsDependabotOrgSecretsForFreeOrgs(t *testing.T) {

	repositorySecrets := map[string]string{
		"my_secret": "hello repo",
	}

	organizationSecrets := map[string]string{
		"my_org_secret": "hello organization",
	}
	secretsForRepository := &kredz.RepositorySecretsResponse{
		OrganizationSecrets: organizationSecrets,
		RepositorySecrets:   repositorySecrets,
	}

	credzMockClient := kredz.MockClient{}
	credzMockClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(secretsForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "free_organization",
		},
	}

	mockGhTwirpClient := &ghtwirp.MockClient{}
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, ownerID.String()).Return(ownerID, nil)
	mockGhTwirpClient.On("GetNextGlobalID", mock.Anything, "secretsAppID").Return(types.GlobalID("secretsAppNextID"), nil)

	secretStore, err := newSecretStore(newTestContext(), &credzMockClient, mockGhTwirpClient, &earthsmoke.MockDecryptor{}, &data, repoID, "secretsAppID", workflowbuild.DependabotSecretSource, logger.TestLogger())
	require.NoError(t, err, "Reading secrets should not error")
	require.NotNil(t, secretStore, "Secrets should not be nil")

	secrets := secretStore.GetEncryptedSecrets()
	require.Equal(t, 2, len(secrets), "Expected %d secrets in secrets map but found %d", 2, len(secrets))

	repoSecret := secrets["my_secret"]
	expectedRepoValue := "hello repo"
	require.Equal(t, expectedRepoValue, repoSecret.Value, "Expected repository secret \"%s\" in secrets map but found \"%s\"", expectedRepoValue, expectedRepoValue)
	require.Equal(t, repoID.String(), repoSecret.Scope, "Expected repository secret to have scope \"%s\" in secrets map but found \"%s\"", repoID.String(), repoSecret.Scope)

	orgSecret := secrets["my_org_secret"]
	expectedOrgValue := "hello organization"
	require.Equal(t, expectedOrgValue, orgSecret.Value, "Expected org secret \"%s\" in secrets map but found \"%s\"", expectedOrgValue, expectedOrgValue)
	require.Equal(t, ownerID.String(), orgSecret.Scope, "Expected org secret to have scope \"%s\" in secrets map but found \"%s\"", ownerID.String(), orgSecret.Scope)
}

func TestGetDecryptedSecretsHandlesError(t *testing.T) {
	mockDecryptor := &earthsmoke.MockDecryptor{}
	secrets := &secretStore{
		encryptedSecretsMap: map[string]build.EncryptedSecret{
			"my_valid_secret": {
				Value: "something_valid",
			},
			"my_invalid_secret": {
				Value: "something_invalid",
			},
		},
		secretDecryptor: mockDecryptor,
		log:             logger.TestLogger(),
	}

	mockDecryptor.On("DecryptSecretValue", mock.Anything, "something_valid", mock.Anything, mock.Anything).Return("something_valid", true, nil).Once()
	mockDecryptor.On("DecryptSecretValue", mock.Anything, "something_invalid", mock.Anything, mock.Anything).Return("", true, errors.New("decrypt error")).Once()

	result := secrets.GetDecryptedSecrets(context.Background())

	assert.NotNil(t, result)
	assert.Equal(t, 1, len(result))
	assert.Equal(t, "something_valid", result["my_valid_secret"])
}

func TestGetDecryptedSecretsHandlesErrorWithNextGlobalIDDecryption(t *testing.T) {
	mockDecryptor := &earthsmoke.MockDecryptor{}
	secrets := &secretStore{
		encryptedSecretsMap: map[string]build.EncryptedSecret{
			"my_secret_1": {
				Value: "something_valid",
			},
			"my_secret_2": {
				Value: "something_valid",
			},
		},
		secretDecryptor: mockDecryptor,
		log:             logger.TestLogger(),
	}

	mockDecryptor.On("DecryptSecretValue", mock.Anything, "something_valid", mock.Anything, mock.Anything, mock.Anything).Return("something_valid", true, nil)
	mockDecryptor.On("DecryptSecretValue", mock.Anything, "something_invalid", mock.Anything, mock.Anything, mock.Anything).Return("", true, errors.New("decrypt error")).Once()

	result := secrets.GetDecryptedSecrets(context.Background())

	assert.NotNil(t, result)
	assert.Equal(t, 2, len(result))
	assert.Equal(t, "something_valid", result["my_secret_1"])
	assert.Equal(t, "something_valid", result["my_secret_2"])
}

func TestGetDecryptedSecretsReturnsLegacyValueWithUnEqualNextDecryptedValue(t *testing.T) {
	mockDecryptor := &earthsmoke.MockDecryptor{}
	secrets := &secretStore{
		encryptedSecretsMap: map[string]build.EncryptedSecret{
			"my_secret_1": {
				Value: "something_valid",
			},
			"my_secret_2": {
				Value: "something_valid",
			},
		},
		secretDecryptor: mockDecryptor,
		log:             logger.TestLogger(),
	}

	mockDecryptor.On("DecryptSecretValue", mock.Anything, "something_valid", mock.Anything, mock.Anything).Return("something_valid", true, nil)

	result := secrets.GetDecryptedSecrets(context.Background())

	assert.NotNil(t, result)
	assert.Equal(t, 2, len(result))
	assert.Equal(t, "something_valid", result["my_secret_1"])
	assert.Equal(t, "something_valid", result["my_secret_2"])
}
