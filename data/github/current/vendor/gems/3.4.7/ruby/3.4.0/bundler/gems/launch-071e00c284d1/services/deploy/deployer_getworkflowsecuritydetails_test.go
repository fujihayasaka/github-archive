package deploy

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

func TestDeployer_GetWorkflowSecurityDetails(t *testing.T) {
	suite.Run(t, new(GetWorkflowSecurityDetailsSuite))
}

type GetWorkflowSecurityDetailsSuite struct {
	suite.Suite

	mockClientFactory  *github.MockClientFactory
	mockClient         *github.MockClient
	mockWorkflowBuilds *deployer.MockWorkflowBuildsRepository

	svc *service
}

const (
	getWorkflowSecurityDetailsSuiteRepositoryID = types.GlobalID("my-rad-repo")
	getWorkflowSecurityDetailsSuiteOwnerID      = types.GlobalID("O_kgDNJr8")
)

var unsafeDependabotEvents = []string{
	"pull_request",
	"pull_request_review",
	"pull_request_review_comment",
	"push",
}

var safeDependabotEvents = []string{
	"pull_request_target",
	"issue_comment",
}

var sendSecretForkPolicy = []types.ForkPRWorkflowsPolicy{
	types.ForkPRWorkflowsRunWithSecrets,
	types.ForkPRWorkflowsRunWithTokensAndSecrets,
}

var noSendSecretForkPolicy = []types.ForkPRWorkflowsPolicy{
	types.ForkPRWorkflowsRunWithTokens,
	types.ForkPRWorkflowsRunWorkflows,
	types.ForkPRWorkflowsDisabled,
}

var allForkPolicies = append(sendSecretForkPolicy, noSendSecretForkPolicy...)

var allPublicForkPolicies = []types.PublicForkPRWorkflowsPolicy{types.PublicForkPRWorkflowsInvalidPolicy, types.PublicForkPRWorkflowsRunWithVariables}

var publicRepoInfo = &github.BasicRepositoryInfo{
	ID:         getWorkflowSecurityDetailsSuiteRepositoryID,
	DatabaseID: 1234,
}

func (s *GetWorkflowSecurityDetailsSuite) SetupTest() {
	s.mockClientFactory = github.NewMockClientFactory()
	s.mockClient = &github.MockClient{}
	s.mockWorkflowBuilds = &deployer.MockWorkflowBuildsRepository{}

	ownerNextID := getWorkflowSecurityDetailsSuiteOwnerID
	s.mockClientFactory.ByRepositoryOwnerID[ownerNextID] = s.mockClient

	s.svc = newTestService()
	s.svc.cfg.ClientFactory = s.mockClientFactory
	s.svc.cfg.WorkflowBuilds = s.mockWorkflowBuilds
}

func (s *GetWorkflowSecurityDetailsSuite) TearDownTest() {
	s.mockClient.AssertExpectations(s.T())
	s.mockWorkflowBuilds.AssertExpectations(s.T())
}

func (s *GetWorkflowSecurityDetailsSuite) assertSvcerr(err error, expectedCode twirp.ErrorCode) bool {
	return s.Assert().Error(err) && s.Assert().Equal(expectedCode, svcerr.ExtractCode(err))
}

func (s *GetWorkflowSecurityDetailsSuite) TestEmptyRequest() {
	ctx := context.Background()

	req := &pb.GetWorkflowSecurityDetailsRequest{
		WorkflowID: "",
	}

	_, err := s.svc.GetWorkflowSecurityDetails(ctx, req)
	s.assertSvcerr(err, twirp.InvalidArgument)
}

func (s *GetWorkflowSecurityDetailsSuite) TestUnknownEventType() {
	ctx := context.Background()

	req := &pb.GetWorkflowSecurityDetailsRequest{
		WorkflowID: "abc123",
	}

	workflowBuildResponse := &deployer.DataForSecurityDetails{
		RepositoryID: getWorkflowSecurityDetailsSuiteRepositoryID,
		Event:        "unknown_event_type",
		EventPayload: []byte(`{ "some": "json" }`),
	}
	s.mockWorkflowBuilds.On("GetDataForSecurityDetails", mock.Anything, "abc123").Return(workflowBuildResponse, true, nil).Once()

	_, err := s.svc.GetWorkflowSecurityDetails(ctx, req)
	s.assertSvcerr(err, twirp.Internal)
}

func (s *GetWorkflowSecurityDetailsSuite) TestWorkflowSecurityDetails() {
	ctx := context.Background()

	tests := []struct {
		name             string
		event            string
		payload          []byte
		prPolicy         types.ForkPRWorkflowsPolicy
		publicPrPolicy   types.PublicForkPRWorkflowsPolicy
		secretsAllowed   bool
		variablesAllowed bool
	}{
		{
			name:             "Secrets and variables always permitted for scheduled run",
			event:            "schedule",
			payload:          deployFixture(s.T(), "schedule.json"),
			prPolicy:         types.ForkPRWorkflowsDisabled,
			publicPrPolicy:   types.PublicForkPRWorkflowsInvalidPolicy,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
		{
			name:             "Secrets and variables always permitted for known non-pull_request webhook event",
			event:            "push",
			payload:          flowEventFixture(s.T(), "push.json"),
			prPolicy:         types.ForkPRWorkflowsDisabled,
			publicPrPolicy:   types.PublicForkPRWorkflowsInvalidPolicy,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
		{
			name:             "Secrets and variables always permitted for intra-repo pull_request event",
			event:            "pull_request",
			payload:          flowEventFixture(s.T(), "pull_request.json"),
			prPolicy:         types.ForkPRWorkflowsDisabled,
			publicPrPolicy:   types.PublicForkPRWorkflowsInvalidPolicy,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
		{
			name:             "Secrets and variables permitted for pull_request_target event",
			event:            "pull_request_target",
			payload:          flowEventFixture(s.T(), "pull_request-from-fork.json"),
			prPolicy:         types.ForkPRWorkflowsRunWorkflows,
			publicPrPolicy:   types.PublicForkPRWorkflowsRunWithVariables,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
		{
			name:             "Secrets and variables not permitted by default for forked repo PR",
			event:            "pull_request",
			payload:          flowEventFixture(s.T(), "pull_request-from-fork.json"),
			prPolicy:         types.ForkPRWorkflowsRunWorkflows,
			publicPrPolicy:   types.PublicForkPRWorkflowsInvalidPolicy,
			secretsAllowed:   false,
			variablesAllowed: false,
		},
		{
			name:             "Secrets and variables not permitted for forked repo PR (tokens policy)",
			event:            "pull_request",
			payload:          flowEventFixture(s.T(), "pull_request-from-fork.json"),
			prPolicy:         types.ForkPRWorkflowsRunWithTokens,
			publicPrPolicy:   types.PublicForkPRWorkflowsInvalidPolicy,
			secretsAllowed:   false,
			variablesAllowed: false,
		},
		{
			name:             "Secrets and variables permitted for fork repo based on policy",
			event:            "pull_request",
			payload:          flowEventFixture(s.T(), "pull_request-from-fork.json"),
			prPolicy:         types.ForkPRWorkflowsRunWithSecrets,
			publicPrPolicy:   types.PublicForkPRWorkflowsRunWithVariables,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
		{
			name:             "Secrets and variables permitted for fork repo based on policy (tokens and secrets)",
			event:            "pull_request",
			payload:          flowEventFixture(s.T(), "pull_request-from-fork.json"),
			prPolicy:         types.ForkPRWorkflowsRunWithTokensAndSecrets,
			publicPrPolicy:   types.PublicForkPRWorkflowsRunWithVariables,
			secretsAllowed:   true,
			variablesAllowed: true,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest
			workflowBuildResponse := &deployer.DataForSecurityDetails{
				RepositoryID: getWorkflowSecurityDetailsSuiteRepositoryID,
				Event:        tc.event,
				EventPayload: tc.payload,
				WorkflowMetadata: &metadata.WorkflowMetadata{
					RepositoryOwner: &metadata.WorkflowMetadataUser{
						GlobalRelayID: types.GlobalID(getWorkflowSecurityDetailsSuiteOwnerID).String(),
					},
				},
			}

			secretPolicies := &github.SecretPolicies{
				CanUseEnvironments:    true,
				ForkPRWorkflowsPolicy: tc.prPolicy,
			}

			publicForkPolicies := &github.Policies{
				CanUseEnvironments:          true,
				ForkPRWorkflowsPolicy:       tc.prPolicy,
				PublicForkPRWorkflowsPolicy: tc.publicPrPolicy,
			}
			mockTwirpClient := &ghtwirp.MockClient{}
			s.svc.cfg.GithubTwirpClient = mockTwirpClient
			s.mockWorkflowBuilds.On("GetDataForSecurityDetails", mock.Anything, "abc123").Return(workflowBuildResponse, true, nil).Once()

			s.mockClient.On("GetSecretPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(secretPolicies, nil).Once()

			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(true)

			s.mockClient.On("GetPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(publicForkPolicies, nil).Once()

			res, err := s.svc.GetWorkflowSecurityDetails(ctx, &pb.GetWorkflowSecurityDetailsRequest{
				WorkflowID: "abc123",
			})

			s.Assert().NotNil(res)
			s.Assert().NoError(err)

			s.Assert().Equal(tc.secretsAllowed, res.GetAreActionsSecretsAllowed())
			s.Assert().Equal(tc.secretsAllowed, res.GetAreActionsEnvironmentSecretsAllowed())
			s.Assert().Equal(tc.variablesAllowed, res.GetAreActionsEnvironmentVariablesAllowed())
			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *GetWorkflowSecurityDetailsSuite) TestWorkflowSecurityDetailsMultiTenant() {
	ctx := context.Background()

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	tests := []struct {
		name          string
		isMultiTenant bool
		ghTenantID    *int64
		expectError   bool
	}{
		{
			name:          "not multi-tenant",
			isMultiTenant: false,
		},
		{
			name:          "multi-tenant, valid tenant ID",
			isMultiTenant: true,
			ghTenantID:    &validGitHubTenantID,
		},
		{
			name:          "multi-tenant, invalid tenant ID",
			isMultiTenant: true,
			ghTenantID:    &invalidGitHubTenantID,
		},
		{
			name:          "multi-tenant, no tenant ID",
			isMultiTenant: true,
			ghTenantID:    nil,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest
			workflowBuildResponse := &deployer.DataForSecurityDetails{
				RepositoryID: getWorkflowSecurityDetailsSuiteRepositoryID,
				Event:        "push",
				EventPayload: flowEventFixture(s.T(), "push.json"),
				WorkflowMetadata: &metadata.WorkflowMetadata{
					RepositoryOwner: &metadata.WorkflowMetadataUser{
						GlobalRelayID: types.GlobalID(getWorkflowSecurityDetailsSuiteOwnerID).String(),
					},
				},
			}

			if tc.isMultiTenant {
				workflowBuildResponse.GitHubTenantID = tc.ghTenantID
			}

			secretPolicies := &github.SecretPolicies{
				CanUseEnvironments:    true,
				ForkPRWorkflowsPolicy: types.ForkPRWorkflowsDisabled,
			}

			publicForkPolicies := &github.Policies{
				CanUseEnvironments:          true,
				ForkPRWorkflowsPolicy:       types.ForkPRWorkflowsDisabled,
				PublicForkPRWorkflowsPolicy: types.PublicForkPRWorkflowsInvalidPolicy,
			}
			mockTwirpClient := &ghtwirp.MockClient{}
			s.svc.cfg.GithubTwirpClient = mockTwirpClient
			s.mockWorkflowBuilds.On("GetDataForSecurityDetails", mock.Anything, "abc123").Return(workflowBuildResponse, true, nil).Once()

			s.mockClient.On("GetSecretPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(secretPolicies, nil).Once()

			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(true)

			s.mockClient.On("GetPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(publicForkPolicies, nil).Once()

			res, err := s.svc.GetWorkflowSecurityDetails(ctx, &pb.GetWorkflowSecurityDetailsRequest{
				WorkflowID: "abc123",
			})

			if tc.expectError {
				s.Assert().Nil(res)
				s.Assert().Error(err)
			} else {
				s.Assert().NotNil(res)
				s.Assert().NoError(err)
			}

			s.TearDownTest() // Need to assert expectations
		})
	}
}

func (s *GetWorkflowSecurityDetailsSuite) TestCannotUseEnvironments() {
	ctx := context.Background()

	workflowBuildResponse := &deployer.DataForSecurityDetails{
		RepositoryID: getWorkflowSecurityDetailsSuiteRepositoryID,
		Event:        "schedule",
		EventPayload: deployFixture(s.T(), "schedule.json"),
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				GlobalRelayID: types.GlobalID(getWorkflowSecurityDetailsSuiteOwnerID).String(),
			},
		},
	}

	secretPolicies := &github.SecretPolicies{
		CanUseEnvironments:    false,
		ForkPRWorkflowsPolicy: types.ForkPRWorkflowsRunWorkflows,
	}

	publicForkPolicies := &github.Policies{
		PublicForkPRWorkflowsPolicy: types.PublicForkPRWorkflowsRunWithVariables,
	}
	mockTwirpClient := &ghtwirp.MockClient{}
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.mockWorkflowBuilds.On("GetDataForSecurityDetails", mock.Anything, "abc123").Return(workflowBuildResponse, true, nil).Once()

	s.mockClient.On("GetSecretPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(secretPolicies, nil).Once()

	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(true)

	s.mockClient.On("GetPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(publicForkPolicies, nil).Once()

	res, err := s.svc.GetWorkflowSecurityDetails(ctx, &pb.GetWorkflowSecurityDetailsRequest{
		WorkflowID: "abc123",
	})

	s.Assert().NotNil(res)
	s.Assert().NoError(err)

	s.Assert().Equal(true, res.GetAreActionsSecretsAllowed())
	s.Assert().Equal(false, res.GetAreActionsEnvironmentSecretsAllowed())
}

// TestDependabotAndActionsSecretUsage verifies untrusted Dependabot-triggered runs aren't passed Actions environment secrets.
func (s *GetWorkflowSecurityDetailsSuite) TestDependabotAndActionsSecretUsage() {
	testCases := []struct {
		name                       string
		events                     []string
		environmentAccessPermitted []bool
		forkPolicies               []types.ForkPRWorkflowsPolicy
		publicForkPolicies         []types.PublicForkPRWorkflowsPolicy
		expectedResponse           *pb.GetWorkflowSecurityDetailsResponse
	}{
		{
			name:                       "all policies allow sending Actions secrets for safe events",
			events:                     safeDependabotEvents,
			environmentAccessPermitted: []bool{true},
			forkPolicies:               allForkPolicies,
			publicForkPolicies:         allPublicForkPolicies,
			expectedResponse: &pb.GetWorkflowSecurityDetailsResponse{
				AreActionsSecretsAllowed:            true,
				AreActionsEnvironmentSecretsAllowed: true,
				IsIDTokenGenerationAllowed:          true,
			},
		},
		{
			name:                       "restrictive policies forbid sending Actions secrets for unsafe events",
			events:                     unsafeDependabotEvents,
			environmentAccessPermitted: []bool{false, true},
			forkPolicies:               noSendSecretForkPolicy,
			publicForkPolicies:         allPublicForkPolicies,
			expectedResponse: &pb.GetWorkflowSecurityDetailsResponse{
				AreActionsSecretsAllowed:            false,
				AreActionsEnvironmentSecretsAllowed: false,
				IsIDTokenGenerationAllowed:          true,
			},
		},
		{
			name:                       "permissive policies don't permit Actions secrets for unsafe Dependabot events",
			events:                     unsafeDependabotEvents,
			environmentAccessPermitted: []bool{true},
			forkPolicies:               sendSecretForkPolicy,
			publicForkPolicies:         allPublicForkPolicies,
			expectedResponse: &pb.GetWorkflowSecurityDetailsResponse{
				AreActionsSecretsAllowed:            false,
				AreActionsEnvironmentSecretsAllowed: false,
				IsIDTokenGenerationAllowed:          true,
			},
		},
		// Environment usage not permitted tests
		{
			name:                       "forbidding environment usage applies to safe events (all policies)",
			events:                     safeDependabotEvents,
			environmentAccessPermitted: []bool{false},
			forkPolicies:               allForkPolicies,
			publicForkPolicies:         allPublicForkPolicies,
			expectedResponse: &pb.GetWorkflowSecurityDetailsResponse{
				AreActionsSecretsAllowed:            true,
				AreActionsEnvironmentSecretsAllowed: false,
				IsIDTokenGenerationAllowed:          true,
			},
		},
		{
			name:                       "forbidding environment usage applies to safe events (permissive policies)",
			events:                     safeDependabotEvents,
			environmentAccessPermitted: []bool{false},
			forkPolicies:               sendSecretForkPolicy,
			publicForkPolicies:         allPublicForkPolicies,
			expectedResponse: &pb.GetWorkflowSecurityDetailsResponse{
				AreActionsSecretsAllowed:            true,
				AreActionsEnvironmentSecretsAllowed: false,
				IsIDTokenGenerationAllowed:          true,
			},
		},
	}

	for _, tc := range testCases {
		if len(tc.environmentAccessPermitted) == 0 {
			panic("you must specify one or more environment policies")
		}
		if len(tc.forkPolicies) == 0 {
			panic("you must specify one or more fork policies")
		}
		if len(tc.events) == 0 {
			panic("you must specify one or more events")
		}

		for _, event := range tc.events {
			for _, forkPolicy := range tc.forkPolicies {
				for _, publicforkPolicy := range tc.publicForkPolicies {
					for _, environmentPolicy := range tc.environmentAccessPermitted {
						s.Run(fmt.Sprintf("%s(event: %s)(fork_policy: %v)(public_fork_policy:%v)(environment_policy: %v)", tc.name, event, forkPolicy, publicforkPolicy, environmentPolicy), func() {
							ctx := context.Background()

							workflowBuildResponse := &deployer.DataForSecurityDetails{
								RepositoryID: getWorkflowSecurityDetailsSuiteRepositoryID,
								Event:        event,
								EventPayload: flowEventFixture(s.T(), event+".json"),
								WorkflowMetadata: &metadata.WorkflowMetadata{
									Actor: &metadata.WorkflowMetadataActor{
										IsDependabot: true,
									},
									RepositoryOwner: &metadata.WorkflowMetadataUser{
										GlobalRelayID: types.GlobalID(getWorkflowSecurityDetailsSuiteOwnerID).String(),
									},
								},
							}

							secretPolicies := &github.SecretPolicies{
								CanUseEnvironments:    environmentPolicy,
								ForkPRWorkflowsPolicy: forkPolicy,
							}

							publicForkPolicies := &github.Policies{
								PublicForkPRWorkflowsPolicy: publicforkPolicy,
							}
							mockTwirpClient := &ghtwirp.MockClient{}
							s.svc.cfg.GithubTwirpClient = mockTwirpClient

							s.mockWorkflowBuilds.On("GetDataForSecurityDetails", mock.Anything, "abc123").Return(workflowBuildResponse, true, nil).Once()

							s.mockClient.On("GetSecretPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(secretPolicies, nil).Once()

							mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(true)

							s.mockClient.On("GetPolicies", mock.Anything, getWorkflowSecurityDetailsSuiteRepositoryID).Return(publicForkPolicies, nil).Once()

							res, err := s.svc.GetWorkflowSecurityDetails(ctx, &pb.GetWorkflowSecurityDetailsRequest{
								WorkflowID: "abc123",
							})

							s.Assert().NotNil(res)
							s.Assert().NoError(err)
							s.Assert().Equal(tc.expectedResponse.AreActionsSecretsAllowed, res.GetAreActionsSecretsAllowed())
							s.Assert().Equal(tc.expectedResponse.AreActionsEnvironmentSecretsAllowed, res.GetAreActionsEnvironmentSecretsAllowed())
							s.Assert().Equal(tc.expectedResponse.IsIDTokenGenerationAllowed, res.GetIsIDTokenGenerationAllowed())
						})
					}
				}
			}
		}
	}
}

// re-use flowEvent fixtures as if they were being retrieved from the database.
func flowEventFixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("../../flow/flowevents/fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}

func deployFixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}
