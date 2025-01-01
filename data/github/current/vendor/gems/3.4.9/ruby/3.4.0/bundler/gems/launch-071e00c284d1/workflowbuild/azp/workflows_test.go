package azp

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

func Test_WorkflowProvider_GetWorkflows(t *testing.T) {
	workflowFile := types.ResolvedFile{
		Path: ".github/workflows/workflow.yaml",
		Text: "some workflow",
		SHA:  "46e3782dbe75596267538a621e6a4ef0a46e55c4",
	}

	type args struct {
		eventName                                       string
		getAdditionalWorkflowsResponse                  func() *ghtwirp.AdditionalWorkflows
		getRequiredWorkflowsProviderResponseForRulesets func() []types.ResolvedFile
		ghe                                             flowevents.GitHubEvent
		data                                            *types.WorkflowInvocationData
		isEnterprise                                    bool
	}

	tests := []struct {
		name string
		args args
		want []types.ResolvedFile
	}{
		{
			name: "Returns pipeline files for push event",
			args: args{
				eventName: flowevents.Push,
				ghe:       makePushEvent("main"),
				data: &types.WorkflowInvocationData{
					PipelineFiles: []types.ResolvedFile{workflowFile},
					RepoGlobalID:  types.GlobalID("sample-repo-id"),
				},
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return nil
				},
			},
			want: []types.ResolvedFile{workflowFile},
		},
		{
			name: "Returns passed yaml for dynamic event",
			args: args{
				eventName: flowevents.Dynamic,
				ghe:       &flowevents.DynamicEvent{Workflow: "some workflow", IntegrationName: "dependabot", Slug: "some-slug"},
				data: &types.WorkflowInvocationData{
					RepoGlobalID:  types.GlobalID("sample-repo-id"),
					PipelineFiles: []types.ResolvedFile{},
					References: types.WorkflowInvocationReferences{
						CheckoutCommit: types.WorkflowInvocationReference{CommitSHA: types.NullCommitSha},
					},
				},
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return nil
				},
			},
			want: []types.ResolvedFile{{
				Path: flowevents.BuildDynamicWorkflowFilePath("dependabot", "some-slug"),
				Text: "some workflow",
				SHA:  string(types.NullCommitSha),
			}},
		},
		{
			name: "Does not return files for pull request event for required workflows",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id-1"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-1",
								Path:    ".github/workflows/test.yml",
								Ref:     "main",
							},
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/test.yml",
								Ref:     "master",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					RepoGlobalID:  types.GlobalID("sample-repo-id"),
					PipelineFiles: []types.ResolvedFile{workflowFile},
				},
			},
			want: []types.ResolvedFile{
				workflowFile,
			},
		},
		{
			name: "Returns workflow files for pull request event for ruleset workflows",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/test.yml",
								Ref:     "main",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{
						{
							RepositoryID: types.GlobalID("sample-repo-id-2"),
							Path:         "required/0/.github/workflows/test.yml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
					}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					PipelineFiles: []types.ResolvedFile{workflowFile},
				},
			},
			want: []types.ResolvedFile{
				{
					RepositoryID: types.GlobalID("sample-repo-id-2"),
					Path:         "required/0/.github/workflows/test.yml",
					Ref:          "main",
					IsTruncated:  false,
					Text:         "ruleset workflow 1 contents",
				},
				workflowFile,
			},
		},
		{
			name: "Returns deduplicated workflow files for pull request event for ruleset and pipeline workflows",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo",
								Path:    ".github/workflows/workflow.yaml",
								Ref:     "main",
							},
							{
								RepoID:  types.GlobalID("sample-repo-id-1"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-1",
								Path:    ".github/workflows/test.yml",
								Ref:     "master",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{
						{
							RepositoryID: types.GlobalID("sample-repo-id"),
							Path:         "required/0/.github/workflows/workflow.yaml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "some workflow",
						},
						{
							RepositoryID: types.GlobalID("sample-repo-id-1"),
							Path:         "required/0/.github/workflows/test.yml",
							Ref:          "master",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
					}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					RepoGlobalID:  types.GlobalID("sample-repo-id"),
					PipelineFiles: []types.ResolvedFile{workflowFile},
				},
			},
			want: []types.ResolvedFile{
				{
					RepositoryID: types.GlobalID("sample-repo-id"),
					Path:         "required/0/.github/workflows/workflow.yaml",
					Ref:          "main",
					IsTruncated:  false,
					Text:         "some workflow",
				},
				{
					RepositoryID: types.GlobalID("sample-repo-id-1"),
					Path:         "required/0/.github/workflows/test.yml",
					Ref:          "master",
					IsTruncated:  false,
					Text:         "ruleset workflow 1 contents",
				},
			},
		},
		{
			name: "Returns pipeline and ruleset files for pull request event in case of GHES",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id-1"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-1",
								Path:    ".github/workflows/ruleset-1.yml",
								Ref:     "main",
							},
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/ruleset-2.yml",
								Ref:     "main",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{
						{
							RepositoryID: types.GlobalID("sample-repo-id-1"),
							Path:         "required/0/.github/workflows/ruleset-1.yml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
						{
							RepositoryID: types.GlobalID("sample-repo-id-2"),
							Path:         "required/0/.github/workflows/ruleset-2.yml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "ruleset workflow 2 contents",
						},
					}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					RepoGlobalID:   types.GlobalID("sample-repo-id"),
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					PipelineFiles: []types.ResolvedFile{workflowFile},
				},
				isEnterprise: true,
			},
			want: []types.ResolvedFile{
				{
					RepositoryID: types.GlobalID("sample-repo-id-1"),
					Path:         "required/0/.github/workflows/ruleset-1.yml",
					Ref:          "main",
					IsTruncated:  false,
					Text:         "ruleset workflow 1 contents",
				},
				{
					RepositoryID: types.GlobalID("sample-repo-id-2"),
					Path:         "required/0/.github/workflows/ruleset-2.yml",
					Ref:          "main",
					IsTruncated:  false,
					Text:         "ruleset workflow 2 contents",
				},
				workflowFile,
			},
		},
		{
			name: "Returns pipeline files for pull request event when the additional workflows call returns error",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					RepoGlobalID:   types.GlobalID("sample-repo-id"),
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					PipelineFiles: []types.ResolvedFile{workflowFile},
					References: types.WorkflowInvocationReferences{
						EventCommit: types.WorkflowInvocationReference{
							CommitSHA: types.CommitSha("asd"),
							GitRef:    types.GitRef("event ref"),
						},
						CheckoutCommit: types.WorkflowInvocationReference{
							GitRef: types.GitRef("checkout ref"),
						},
					},
				},
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return nil
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return nil
				},
			},
			want: []types.ResolvedFile{workflowFile},
		},
		{
			name: "Returns workflow files for merge queue event for ruleset workflows",
			args: args{
				eventName: flowevents.MergeGroup,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/test.yml",
								Ref:     "main",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{
						{
							RepositoryID: types.GlobalID("sample-repo-id-2"),
							Path:         "required/0/.github/workflows/test.yml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
					}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
					PipelineFiles: []types.ResolvedFile{workflowFile},
				},
			},
			want: []types.ResolvedFile{
				{
					RepositoryID: types.GlobalID("sample-repo-id-2"),
					Path:         "required/0/.github/workflows/test.yml",
					Ref:          "main",
					IsTruncated:  false,
					Text:         "ruleset workflow 1 contents",
				},
				workflowFile,
			},
		},
	}
	for _, tt := range tests {

		t.Run(tt.name, func(t *testing.T) {
			mockGhTwirpClient := &ghtwirp.MockClient{}
			mockRequiredWorkflowsProvider := &MockRequiredWorkflowsProvider{}
			w := &workflowProvider{
				requiredWorkflowsProvider: mockRequiredWorkflowsProvider,
				obs:                       observability.NewNullObservability(),
				ghTwirpClient:             mockGhTwirpClient,
				isEnterprise:              tt.args.isEnterprise,
			}

			mockGhTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.MatchEnvPathLabRulesetWorkflows, mock.Anything).Return(true)

			additionalWorkflowsResponse := tt.args.getAdditionalWorkflowsResponse()

			event := ghtwirp.EventReference{
				BaseRef:   "",
				BeforeOid: "",
				AfterOid:  "",
				Type:      tt.args.eventName,
			}

			if tt.args.eventName == flowevents.PullRequest {
				event = ghtwirp.EventReference{
					BaseRef:   "refs/heads/master",
					BeforeOid: "abcdef",
					AfterOid:  "",
					Type:      tt.args.eventName,
				}
			}

			if additionalWorkflowsResponse != nil {
				mockGhTwirpClient.EXPECT().GetAdditionalWorkflows(mock.Anything, tt.args.data.RepoDatabaseID, event).Return(additionalWorkflowsResponse, nil)

				if len(additionalWorkflowsResponse.RulesetWorkflows) > 0 {
					mockRequiredWorkflowsProvider.EXPECT().GetRequiredWorkflowFiles(mock.Anything, additionalWorkflowsResponse.RulesetWorkflows, tt.args.eventName, tt.args.data.RepoDatabaseID, tt.args.data.Actor.DatabaseID).Return(tt.args.getRequiredWorkflowsProviderResponseForRulesets()).Once()
				}
			} else {
				mockGhTwirpClient.EXPECT().GetAdditionalWorkflows(mock.Anything, tt.args.data.RepoDatabaseID, event).Return(nil, errors.New("internal error"))
			}

			got := w.GetWorkflows(context.Background(), tt.args.eventName, tt.args.ghe, tt.args.data)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("workflowProvider.GetWorkflows() = %v, want %v", got, tt.want)
			}
		})
	}
}

func Test_WorkflowProvider_GetAdditionalWorkflows(t *testing.T) {
	type args struct {
		eventName                                       string
		getAdditionalWorkflowsResponse                  func() *ghtwirp.AdditionalWorkflows
		getRequiredWorkflowsProviderResponseForRulesets func() []types.ResolvedFile
		ghe                                             flowevents.GitHubEvent
		data                                            *types.WorkflowInvocationData
		isEnterprise                                    bool
	}

	type ResolvedAdditionalWorkflowFiles struct {
		rulesetWorkflows []types.ResolvedFile
	}

	tests := []struct {
		name string
		args args
		want ResolvedAdditionalWorkflowFiles
	}{
		{
			name: "Checks that GetAdditionalWorkflows correctly adds ruleset workflows to resolvedAdditionalWorkflowFiles",
			args: args{
				eventName: flowevents.PullRequest,
				ghe:       makePullRequest("main"),
				getAdditionalWorkflowsResponse: func() *ghtwirp.AdditionalWorkflows {
					return &ghtwirp.AdditionalWorkflows{
						RulesetWorkflows: []*ghtwirp.RequiredWorkflow{
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/test.yml",
								Ref:     "main",
							},
							{
								RepoID:  types.GlobalID("sample-repo-id-2"),
								OwnerID: types.GlobalID("sample-owner-id"),
								RepoNwo: "test-org/test-repo-2",
								Path:    ".github/workflows/test.yml",
								Ref:     "master",
							},
						},
					}
				},
				getRequiredWorkflowsProviderResponseForRulesets: func() []types.ResolvedFile {
					return []types.ResolvedFile{
						{
							RepositoryID: types.GlobalID("sample-repo-id-2"),
							Path:         "required/0/.github/workflows/test.yml",
							Ref:          "main",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
						{
							RepositoryID: types.GlobalID("sample-repo-id-2"),
							Path:         "required/0/.github/workflows/test.yml",
							Ref:          "master",
							IsTruncated:  false,
							Text:         "ruleset workflow 1 contents",
						},
					}
				},
				data: &types.WorkflowInvocationData{
					RepoDatabaseID: 1,
					Actor: types.WorkflowInvocationActorData{
						DatabaseID: 2,
					},
				},
			},
			want: ResolvedAdditionalWorkflowFiles{
				rulesetWorkflows: []types.ResolvedFile{
					{
						RepositoryID: types.GlobalID("sample-repo-id-2"),
						Path:         "required/0/.github/workflows/test.yml",
						Ref:          "main",
						IsTruncated:  false,
						Text:         "ruleset workflow 1 contents",
					},
					{
						RepositoryID: types.GlobalID("sample-repo-id-2"),
						Path:         "required/0/.github/workflows/test.yml",
						Ref:          "master",
						IsTruncated:  false,
						Text:         "ruleset workflow 1 contents",
					},
				},
			},
		},
	}
	for _, tt := range tests {

		t.Run(tt.name, func(t *testing.T) {
			mockGhTwirpClient := &ghtwirp.MockClient{}

			mockRequiredWorkflowsProvider := &MockRequiredWorkflowsProvider{}
			w := &workflowProvider{
				requiredWorkflowsProvider: mockRequiredWorkflowsProvider,
				obs:                       observability.NewNullObservability(),
				ghTwirpClient:             mockGhTwirpClient,
				isEnterprise:              tt.args.isEnterprise,
			}

			mockGhTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.MatchEnvPathLabRulesetWorkflows, mock.Anything).Return(true)

			additionalWorkflowsResponse := tt.args.getAdditionalWorkflowsResponse()

			event := ghtwirp.EventReference{
				BaseRef:   tt.args.data.References.CheckoutCommit.GitRef,
				BeforeOid: "",
				AfterOid:  "",
				Type:      tt.args.eventName,
			}

			var providerRulesetWorkflows = tt.args.getRequiredWorkflowsProviderResponseForRulesets()

			if additionalWorkflowsResponse != nil {
				mockGhTwirpClient.EXPECT().GetAdditionalWorkflows(mock.Anything, tt.args.data.RepoDatabaseID, event).Return(additionalWorkflowsResponse, nil)
				mockRequiredWorkflowsProvider.EXPECT().GetRequiredWorkflowFiles(mock.Anything, mock.Anything, tt.args.eventName, tt.args.data.RepoDatabaseID, tt.args.data.Actor.DatabaseID).Return(providerRulesetWorkflows).Once()
			}

			got, _ := w.getAdditionalWorkflows(context.Background(), tt.args.data, tt.args.eventName, mock.Anything)
			require.EqualValues(t, tt.want, got)
		})
	}
}

func TestMatchesWorkflowsForEnvironment(t *testing.T) {
	type args struct {
		environment         launchconfig.AppEnv
		additionalWorkflows []*ghtwirp.RequiredWorkflow
	}

	tests := []struct {
		name string
		args args
		want []*ghtwirp.RequiredWorkflow
	}{
		{
			name: "returnsNonLabWorkflowsForLabEnvironment",
			args: args{
				environment: launchconfig.ProductionAppEnv,
				additionalWorkflows: []*ghtwirp.RequiredWorkflow{
					{
						RepoID:  types.GlobalID("sample-repo-id-2"),
						OwnerID: types.GlobalID("sample-owner-id"),
						RepoNwo: "test-org/test-repo-2",
						Path:    ".github/workflows-lab/test.yml",
						Ref:     "main",
					},
					{
						RepoID:  types.GlobalID("sample-repo-id-2"),
						OwnerID: types.GlobalID("sample-owner-id"),
						RepoNwo: "test-org/test-repo-2",
						Path:    ".github/workflows/test.yml",
						Ref:     "master",
					},
				},
			},
			want: []*ghtwirp.RequiredWorkflow{
				{
					RepoID:  types.GlobalID("sample-repo-id-2"),
					OwnerID: types.GlobalID("sample-owner-id"),
					RepoNwo: "test-org/test-repo-2",
					Path:    ".github/workflows/test.yml",
					Ref:     "master",
				},
			},
		},
		{
			name: "returnsLabWorkflowsForLabEnvironment",
			args: args{
				environment: launchconfig.LabAppEnv,
				additionalWorkflows: []*ghtwirp.RequiredWorkflow{
					{
						RepoID:  types.GlobalID("sample-repo-id-2"),
						OwnerID: types.GlobalID("sample-owner-id"),
						RepoNwo: "test-org/test-repo-2",
						Path:    ".github/workflows/test.yml",
						Ref:     "main",
					},
					{
						RepoID:  types.GlobalID("sample-repo-id-2"),
						OwnerID: types.GlobalID("sample-owner-id"),
						RepoNwo: "test-org/test-repo-2",
						Path:    ".github/workflows-lab/test.yml",
						Ref:     "master",
					},
				},
			},
			want: []*ghtwirp.RequiredWorkflow{
				{
					RepoID:  types.GlobalID("sample-repo-id-2"),
					OwnerID: types.GlobalID("sample-owner-id"),
					RepoNwo: "test-org/test-repo-2",
					Path:    ".github/workflows-lab/test.yml",
					Ref:     "master",
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := AdditionalWorkflowsForEnvironment(tt.args.additionalWorkflows, tt.args.environment, true)
			require.EqualValues(t, tt.want, got)
		})
	}
}
