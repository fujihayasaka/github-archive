package github

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

var (
	testRepoGlobalID   = types.GlobalID(testutils.EncodeGlobalID("Repository", 1234567))
	testRepoDatabaseID = int64(3)
	testUserGlobalID   = types.GlobalID("U_kgDOAAjmPw")
	testUserDatabaseID = int64(583231)
	testOrgGlobalID    = types.GlobalID("O_kgDNJr8")
	testOrgDatabaseID  = int64(9919)
	testPermissions    = &tokens.InstallationPermissions{
		Checks:      tokens.WriteAccess,
		Deployments: tokens.ReadAccess,
		Pages:       tokens.NoneAccess,
	}
	testExtendedPermissions = &tokens.ExtendedPermissions{
		PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
			Number: 1,
			Permissions: tokens.PullRequestInstallationPermissions{
				Sarifs: tokens.WriteAccess,
			},
		},
	}
)

func newTestClientFactory(t *testing.T, tokenService tokens.Service, ghTwirpClient ghtwirp.Client) Factory {
	obs := observability.NewNullObservability()
	apiURLs, err := cu.TestGraphQLURLProviderWithDefaults()
	if err != nil {
		t.Fatalf("error creating default test url provider: %v", err)
	}

	return &clientFactory{
		env:           launchconfig.TestAppEnv,
		apiURLs:       apiURLs,
		serviceToken:  tokens.NullServiceToken,
		tokenService:  tokenService,
		obs:           obs,
		hooks:         &ClientHooks{},
		ghTwirpClient: ghTwirpClient,
	}
}

func TestNewClientForRepositoryOwnerDatabaseID(t *testing.T) {
	type args struct {
		repoID  types.GlobalID
		ownerID int64
	}
	var tests = []struct {
		name        string
		args        args
		expectError bool
		setup       func(*testing.T, *tokens.MockService, *ghtwirp.MockClient)
	}{
		{
			name: "success for repository and org owners",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgDatabaseID,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepositoryOwner(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "success for 0 owner database id",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: 0,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepositoryOwner(
					mock.Anything,
					testRepoGlobalID,
					int64(1),
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
				mockGhTwirpClient.EXPECT().GetRepositoryOwnerID(mock.Anything, mock.Anything, true).Return(int64(1), nil)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockTokenService := tokens.NewMockService(t)
			mockGhTwirpClient := ghtwirp.NewMockClient(t)
			tt.setup(t, mockTokenService, mockGhTwirpClient)

			cf := newTestClientFactory(t, mockTokenService, mockGhTwirpClient)

			client, err := cf.NewClientForRepositoryOwnerDatabaseID(context.Background(), tt.args.repoID, tt.args.ownerID)
			if tt.expectError {
				assert.Error(t, err)
				assert.Nil(t, client)
			} else {
				require.NoError(t, err)
				assert.NotNil(t, client)
			}
		})
	}
}

func TestNewClientForRepositoryOwner(t *testing.T) {
	type args struct {
		repoID  types.GlobalID
		ownerID types.GlobalID
	}
	var tests = []struct {
		name        string
		args        args
		expectError bool
		setup       func(*testing.T, *tokens.MockService, *ghtwirp.MockClient)
	}{
		{
			name: "fails when non-owner type is passed",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testRepoGlobalID,
			},
			expectError: true,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.AssertNotCalled(t, "SiteScopedTokenForRepositoryOwner")
			},
		},
		{
			name: "success for repository and org owners",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgGlobalID,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepositoryOwner(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "success for repository user owner",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testUserGlobalID,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepositoryOwner(
					mock.Anything,
					testRepoGlobalID,
					testUserDatabaseID,
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "success for nil owner global id",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: types.NilGlobalID,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepositoryOwner(
					mock.Anything,
					testRepoGlobalID,
					int64(1),
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
				mockGhTwirpClient.EXPECT().GetRepositoryOwnerID(mock.Anything, mock.Anything, true).Return(int64(1), nil)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockTokenService := tokens.NewMockService(t)
			mockGhTwirpClient := ghtwirp.NewMockClient(t)
			tt.setup(t, mockTokenService, mockGhTwirpClient)

			cf := newTestClientFactory(t, mockTokenService, mockGhTwirpClient)

			client, err := cf.NewClientForRepositoryOwner(context.Background(), tt.args.repoID, tt.args.ownerID)
			if tt.expectError {
				assert.Error(t, err)
				assert.Nil(t, client)
			} else {
				require.NoError(t, err)
				assert.NotNil(t, client)
			}
		})
	}
}

func TestNewClientForRepository(t *testing.T) {
	type args struct {
		repoID  types.GlobalID
		ownerID types.GlobalID
		opts    *ClientTokenOptions
	}
	var tests = []struct {
		name        string
		args        args
		expectError bool
		setup       func(*testing.T, *tokens.MockService, *ghtwirp.MockClient)
	}{
		{
			name: "fails when non-owner type is passed",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testRepoGlobalID,
				opts:    nil,
			},
			expectError: true,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.AssertNotCalled(t, "SiteScopedTokenForRepository")
			},
		},
		{
			name: "success for repository and org owners",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgGlobalID,
				opts:    nil,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					false,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "success for repository user owner",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testUserGlobalID,
				opts:    nil,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					testUserDatabaseID,
					false,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "sets cache",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgGlobalID,
				opts: &ClientTokenOptions{
					UseTokenCache: true,
				},
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					true,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "sets permissions",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgGlobalID,
				opts: &ClientTokenOptions{
					TokenPermissions: testPermissions,
				},
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					false,
					testPermissions,
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "sets extended permissions",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: testOrgGlobalID,
				opts: &ClientTokenOptions{
					ExtendedPermissions: testExtendedPermissions,
				},
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					testOrgDatabaseID,
					false,
					&tokens.InstallationPermissions{},
					testExtendedPermissions,
				).Return(&tokens.AccessToken{}, nil)
			},
		},
		{
			name: "returns successfully for nil owner global id",
			args: args{
				repoID:  testRepoGlobalID,
				ownerID: types.NilGlobalID,
				opts:    nil,
			},
			expectError: false,
			setup: func(t *testing.T, mockTokenService *tokens.MockService, mockGhTwirpClient *ghtwirp.MockClient) {
				mockTokenService.EXPECT().SiteScopedTokenForRepository(
					mock.Anything,
					testRepoGlobalID,
					int64(1),
					false,
					&tokens.InstallationPermissions{},
					mock.Anything,
				).Return(&tokens.AccessToken{}, nil)
				mockGhTwirpClient.EXPECT().GetRepositoryOwnerID(mock.Anything, mock.Anything, true).Return(int64(1), nil)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockTokenService := tokens.NewMockService(t)
			mockGhTwirpClient := ghtwirp.NewMockClient(t)
			tt.setup(t, mockTokenService, mockGhTwirpClient)

			cf := newTestClientFactory(t, mockTokenService, mockGhTwirpClient)

			client, err := cf.NewClientForRepository(context.Background(), tt.args.repoID, tt.args.ownerID, tt.args.opts)
			if tt.expectError {
				assert.Error(t, err)
				assert.Nil(t, client)
			} else {
				require.NoError(t, err)
				assert.NotNil(t, client)
			}
		})
	}
}
