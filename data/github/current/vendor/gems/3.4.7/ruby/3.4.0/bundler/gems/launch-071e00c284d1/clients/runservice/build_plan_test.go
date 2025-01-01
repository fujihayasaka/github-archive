package runservice

import (
	"context"
	"encoding/json"
	"reflect"
	testing "testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/actions-expressions/go/data"
	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/expressions"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/build"
)

const workflowFilePath = ".github/workflows/workflow.yml"

const dynamicWorkflowFilePath = "dynamic/pages/test"

const requiredWorkflowFilePath = "required/12345/.github/workflows/workflow.yml"

const workflowExample = `# This is a basic workflow to help you get started with Actions

name: CI

# Controls when the workflow will run
on:
  # Triggers the workflow on push or pull request events but only for the "main" branch
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

# A workflow run is made up of one or more jobs that can run sequentially or in parallel
jobs:
  # This workflow contains a single job called "build"
  build:
    # The type of runner that the job will run on
    runs-on: [ self-hosted ]

    # Steps represent a sequence of tasks that will be executed as part of the job
    steps:
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - uses: actions/checkout@v3

      # Runs a single command using the runners shell
      - name: Run a one-line script
        run: echo Hello, world!

      # Runs a set of commands using the runners shell
      - name: Run a multi-line script
        run: |
          echo Add other actions to build,
          echo test, and deploy your project.
`

const parsedExample = `[
  {
    "Name": "build",
    "DisplayName": "build",
    "JobFactory": {
      "Steps": [
        {
          "Reference": {
            "Type": 1,
            "Name": "actions/checkout",
            "Ref": "v3",
            "RepositoryType": "GitHub"
          },
          "ContextName": "__actions_checkout",
          "Condition": "success()",
          "Name": "__actions_checkout"
        },
        {
          "Reference": {
            "Type": 3
          },
          "ContextName": "__run",
          "Condition": "success()",
          "Name": "__run",
          "Inputs": {
            "type": 2,
            "mappingValues": {
              "script": {
                "file": 1,
                "line": 30,
                "col": 14,
                "stringValue": "echo Hello, world!"
              }
            }
          },
          "DisplayNameToken": {
            "file": 1,
            "line": 29,
            "col": 15,
            "stringValue": "Run a one-line script"
          }
        },
        {
          "Reference": {
            "Type": 3
          },
          "ContextName": "__run_2",
          "Condition": "success()",
          "Name": "__run_2",
          "Inputs": {
            "type": 2,
            "mappingValues": {
              "script": {
                "file": 1,
                "line": 34,
                "col": 14,
                "stringValue": "echo Add other actions to build,\necho test, and deploy your project.\n"
              }
            }
          },
          "DisplayNameToken": {
            "file": 1,
            "line": 33,
            "col": 15,
            "stringValue": "Run a multi-line script"
          }
        }
      ],
      "JobDisplayName": "build",
      "JobTarget": [
        "self-hosted"
      ],
      "ActionsEnvironment": {}
    }
  }
]`

func TestBuildPlan_IncludesPlanID(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.Equal(t, wfb.ExecutionID.String(), req.PlanId)
}

func TestBuildPlan_IncludesRightConfiguration(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Configuration.MainFilePath)
	require.NotEmpty(t, req.Configuration.Callbacks)
	require.NotEmpty(t, req.Configuration.Callbacks.SignatureKey)
	require.NotEmpty(t, req.Configuration.Callbacks.PreJobUrl)
	require.NotEmpty(t, req.Configuration.Callbacks.ReceiverUrl)
	require.NotEmpty(t, req.Configuration.OidcConfig.SubClaimCustomizationTemplate)
	require.NotEmpty(t, req.Configuration.OidcConfig.CustomizeEnterpriseIssuer)
}

func TestBuildPlan_IncludesGitHubEventInfo(t *testing.T) {
	wfb := baseWorkflowBuild()
	wfb.AbuseContext = &types.ActionsAbuseTriggerInfo{
		TargetRepositoryTier: 1,
	}
	wfb.CustomerLabel = "github"
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Context.GithubEventInfo)
	require.NotEmpty(t, req.Context.GithubEventInfo.InvokingEventTime)
	require.Equal(t, wfb.OriginTime.UTC(), req.Context.GithubEventInfo.InvokingEventTime.AsTime())
	require.NotEmpty(t, req.Context.GithubEventInfo.CustomerLabel)
	require.Equal(t, uint32(1), req.Context.GithubEventInfo.AbuseInfo.TargetRepositoryTier)
}

func TestBuildPlan_IncludesFeatures(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	features := map[string]bool{
		"feature":  true,
		"featues2": false,
	}

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, features, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Features)
	require.True(t, reflect.DeepEqual(features, req.Features))
}

func TestBuildPlan_IncludesProperties(t *testing.T) {
	wfb := baseWorkflowBuild()
	wfb.RunEnvironment.SelfHostedRunnersDisabled = true
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	properties := &runservice.Properties{
		RepoSelfHostedRunnersDisabled: true,
	}

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Context.Properties)
	require.True(t, reflect.DeepEqual(properties, req.Context.Properties))
}

func TestBuildPlan_IncludesVariables(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	variables := map[string]string{
		"VAR_0": "TESTING_0",
		"VAR_1": "TESTING_1",
	}

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, variables, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Variables)
	require.True(t, reflect.DeepEqual(variables, req.Variables))
}

func TestBuildPlan_IncludesSecrets(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	secretsUnencrypted := map[string]string{
		"SECRET_A": "VERY_SECRET_1",
		"SECRET_B": "VERY_SECRET_2",
		"SECRET_C": "ANOTHER_SECRET",
	}

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "Actions", secretsUnencrypted, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.NotEmpty(t, req.Secrets)
	require.True(t, reflect.DeepEqual(secretsUnencrypted, req.Secrets))
}

func TestBuildPlan_IncludesExpressionContext(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "Actions", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	// Build an expected expression context to compare against.
	expData, err := expressions.NewGitHubContext(ctx, obs, wfb, "Actions")
	require.NoError(t, err)
	b, _ := json.Marshal(data.NewDictionary(
		data.Pair{Key: "github", Value: expData},
		data.Pair{Key: "inputs", Value: data.NewDictionary()},
	))

	require.NotEmpty(t, req.ExpressionData)
	require.True(t, reflect.DeepEqual(string(b), req.ExpressionData))
}

func TestBuildPlan_IncludesRerunContext(t *testing.T) {
	wfb := baseWorkflowBuild()
	wfb.RerunInfo = &types.RerunInfo{
		PlanID: "previous_plan_id",
		JobIDs: []string{"previous_job_id", "another_previous_job_id"},
	}
	wfb.PreviousOrchContexts = []string{"context_1", "context_2"}
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)
	require.NotNil(t, req.RerunContext)
	require.EqualValues(t, wfb.RerunInfo.PlanID, req.RerunContext.PlanId)
	require.EqualValues(t, wfb.RerunInfo.JobIDs, req.RerunContext.RerunJobUuids)
	require.EqualValues(t, wfb.PreviousOrchContexts, req.RerunContext.RerunOrchestrationContexts)
}

func TestBuildPlan_IncludesRunTenantInfo(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	repoTenantInfo := &types.RepositoryTenantInfo{
		RepoTenantInfo: &runservice.TenantInfo{
			Id: "repo_tenant_id",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.example.com/repo_tenant_id",
				"CacheService":     "https://cache.example.com/repo_tenant_id",
			},
		},
	}

	repoTenantInfo.OwnerTenantInfo = &runservice.TenantInfo{
		Id: "org_tenant_id",
		Urls: map[string]string{
			"PipelinesService": "https://pipelines.example.com/org_tenant_id",
		},
	}

	repoTenantInfo.EnterpriseTenantInfo = &runservice.TenantInfo{
		Id: "enterprise_tenant_id",
		Urls: map[string]string{
			"PipelinesService": "https://pipelines.example.com/enterprise_tenant_id",
		},
	}

	req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "Actions", nil, nil, nil, repoTenantInfo)
	require.NoError(t, err)
	require.NotNil(t, req)
	require.EqualValues(t, req.Context.RepositoryTenantInfo.Id, "repo_tenant_id")
	require.EqualValues(t, req.Context.RepositoryTenantInfo.Urls["PipelinesService"], "https://pipelines.example.com/repo_tenant_id")
	require.EqualValues(t, req.Context.RepositoryTenantInfo.Urls["CacheService"], "https://cache.example.com/repo_tenant_id")
	require.EqualValues(t, req.Context.OrganizationTenantInfo.Id, "org_tenant_id")
	require.EqualValues(t, req.Context.OrganizationTenantInfo.Urls["PipelinesService"], "https://pipelines.example.com/org_tenant_id")
	require.EqualValues(t, req.Context.EnterpriseTenantInfo.Id, "enterprise_tenant_id")
	require.EqualValues(t, req.Context.EnterpriseTenantInfo.Urls["PipelinesService"], "https://pipelines.example.com/enterprise_tenant_id")
}

func TestBuildPlan_IncludesMoreContext(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	customerID := int64(12345)
	md := &metadata.WorkflowMetadata{
		InvokingUser: &metadata.WorkflowMetadataUser{
			GlobalRelayID: "user_global_id",
			ID:            123,
			Login:         "test_user",
		},
		CustomerID: &customerID,
	}
	css := &types.CheckSuiteState{
		FlowIdentifier: "my_workflow",
		EventRef:       types.DefaultBranch,
		EventSHA:       types.NullCommitSha,
	}

	req, err := buildPlan(ctx, obs, wft, wfb, md, css, "https://example.com", "https://publicexample.com", "https://example.com", "Actions", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.Equal(t, "my_workflow", req.Context.WorkflowName)
	require.Equal(t, types.DefaultBranch.String(), req.Context.GithubEventInfo.InvokingEventRef)
	require.Equal(t, types.NullCommitSha.String(), req.Context.GithubEventInfo.InvokingEventSha)

	require.Equal(t, "user_global_id", req.Context.GithubEventInfo.InvokingUserId)
	require.Equal(t, "test_user", req.Context.GithubEventInfo.InvokingUserName)
	require.Equal(t, int64(123), req.Context.GithubEventInfo.InvokingUserDatabaseId)

	require.Equal(t, "push", req.Context.GithubEventInfo.InvokingEventType)

	require.Equal(t, int64(9919), req.Context.BillingPlanOwner.DatabaseId)
	require.Equal(t, customerID, req.Context.BillingPlanOwner.CustomerId)
}

func TestBuildPlan_IncludesMoreContext_Enterprise(t *testing.T) {
	wfb := baseWorkflowBuild()
	ctx := context.Background()
	obs := observability.NewNullObservability()

	wfb.ActionsBillingPlanOwner.ID = types.NewGlobalID(context.Background(), "E_kgDNLMw")
	wfb.ActionsBillingPlanOwner.Type = "Business"
	wfb.ActionsBillingPlanOwner.RepositoryOwnerID = types.NewGlobalID(context.Background(), "O_kgDNJr8")
	wfb.ActionsBillingPlanOwner.RepositoryOwnerName = "github"
	wfb.ActionsBillingPlanOwner.RepositoryOwnerDatabaseID = int64(9919)

	wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, wft)
	require.Empty(t, wft.Errors)

	customerID := int64(12345)
	md := &metadata.WorkflowMetadata{
		InvokingUser: &metadata.WorkflowMetadataUser{
			GlobalRelayID: "user_global_id",
			ID:            123,
			Login:         "test_user",
		},
		CustomerID: &customerID,
	}
	css := &types.CheckSuiteState{
		FlowIdentifier:          "my_workflow",
		EventRef:                types.DefaultBranch,
		EventSHA:                types.NullCommitSha,
		WorkflowBuildDatabaseID: int64(9999),
	}

	req, err := buildPlan(ctx, obs, wft, wfb, md, css, "https://example.com", "https://publicexample.com", "https://example.com", "Actions", nil, nil, nil, nil)
	require.NoError(t, err)
	require.NotNil(t, req)

	require.Equal(t, "my_workflow", req.Context.WorkflowName)
	require.Equal(t, int64(9999), req.Context.WorkflowBuildDatabaseId)
	require.Equal(t, types.DefaultBranch.String(), req.Context.GithubEventInfo.InvokingEventRef)
	require.Equal(t, types.NullCommitSha.String(), req.Context.GithubEventInfo.InvokingEventSha)

	require.Equal(t, "user_global_id", req.Context.GithubEventInfo.InvokingUserId)
	require.Equal(t, "test_user", req.Context.GithubEventInfo.InvokingUserName)
	require.Equal(t, int64(123), req.Context.GithubEventInfo.InvokingUserDatabaseId)

	require.Equal(t, "push", req.Context.GithubEventInfo.InvokingEventType)

	require.Equal(t, int64(9919), req.Context.BillingPlanOwner.OrganizationDatabaseId)
	require.Equal(t, "github", req.Context.BillingPlanOwner.OrganizationName)
	require.Equal(t, int64(11468), req.Context.BillingPlanOwner.DatabaseId)
	require.Equal(t, customerID, req.Context.BillingPlanOwner.CustomerId)

}

func TestBuildPlan_IncludesMainFilePath(t *testing.T) {
	tests := []struct {
		desc         string
		build        *build.WorkflowBuild
		expectedPath string
	}{
		{
			desc:         "Regular workflow",
			build:        baseWorkflowBuild(),
			expectedPath: workflowFilePath,
		},
		{
			desc:         "Dynamic workflow",
			build:        dynamicWorkflowBuild(),
			expectedPath: dynamicWorkflowFilePath,
		},
		{
			desc:         "Required workflow",
			build:        requiredWorkflowBuild(),
			expectedPath: requiredWorkflowFilePath,
		},
	}

	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {
			wfb := tc.build
			ctx := context.Background()
			obs := observability.NewNullObservability()

			wft, err := wfparser.LoadWorkflow(ctx, obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, obs, wfb.WorkflowReferencedFiles(false)), types.LimitedReadWorkflowPermissions)
			require.NoError(t, err)
			require.NotNil(t, wft)
			require.Empty(t, wft.Errors)

			req, err := buildPlan(ctx, obs, wft, wfb, nil, nil, "https://example.com", "https://publicexample.com", "https://example.com", "", nil, nil, nil, nil)
			require.NoError(t, err)
			require.NotNil(t, req)

			require.Equal(t, wfb.ExecutionID.String(), req.PlanId)
			require.Equal(t, tc.expectedPath, req.Configuration.MainFilePath)
		})
	}
}

func baseWorkflowBuild() *build.WorkflowBuild {
	return &build.WorkflowBuild{
		ActionsBillingPlanOwner: build.ActionsBillingPlanOwner{
			ID: types.NewGlobalID(context.Background(), "O_kgDNJr8"),
		},
		ExecutionID: types.NewRandomWorkflowExecutionID(),
		SigningKey: &hkdf.DerivedKey{
			WorkflowID: "test-id",
			Timestamp:  time.Now(),
			Key:        []byte("key"),
		},
		WorkflowFilePath: workflowFilePath,
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: workflowFilePath,
				Text: workflowExample,
			},
		},
		EventPayload: []byte("{}"),
		Event:        "push",
		OriginTime:   time.Now(),
		RunEnvironment: build.RunEnvironment{
			OidcSubClaimCustomizationTemplate: "test-template",
			CustomizeEnterpriseOidcIssuer:     true,
		},
	}
}

func dynamicWorkflowBuild() *build.WorkflowBuild {
	return &build.WorkflowBuild{
		ActionsBillingPlanOwner: build.ActionsBillingPlanOwner{
			ID: types.NewGlobalID(context.Background(), "O_kgDNJr8"),
		},
		ExecutionID: types.NewRandomWorkflowExecutionID(),
		SigningKey: &hkdf.DerivedKey{
			WorkflowID: "test-id",
			Timestamp:  time.Now(),
			Key:        []byte("key"),
		},
		WorkflowFilePath: dynamicWorkflowFilePath,
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: dynamicWorkflowFilePath,
				Text: workflowExample,
			},
		},
		EventPayload: []byte("{}"),
		Event:        "push",
	}
}

func requiredWorkflowBuild() *build.WorkflowBuild {
	return &build.WorkflowBuild{
		ActionsBillingPlanOwner: build.ActionsBillingPlanOwner{
			ID: types.NewGlobalID(context.Background(), "O_kgDNJr8"),
		},
		ExecutionID: types.NewRandomWorkflowExecutionID(),
		SigningKey: &hkdf.DerivedKey{
			WorkflowID: "test-id",
			Timestamp:  time.Now(),
			Key:        []byte("key"),
		},
		WorkflowFilePath: requiredWorkflowFilePath,
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: requiredWorkflowFilePath,
				Text: workflowExample,
			},
		},
		EventPayload: []byte("{}"),
		Event:        "push",
	}
}
