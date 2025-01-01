package azp

import (
	"mime/multipart"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/types"
)

func TestToMultipartPayload(t *testing.T) {
	pati := types.PartialAbuseTriggerInfo{
		TriggerEvent:       "push",
		TriggerEventAction: "",
		Actor: &types.ActionsAbuseUser{
			ID:        "MDQ6VXNlcjE2NjMxMDQy",
			Name:      "jclem",
			Type:      "User",
			Plan:      "free",
			CreatedAt: time.Time{},
			IsHammy:   true,
		},
		TargetRepoOwner: &types.ActionsAbuseUser{
			ID:        "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
			Name:      "github",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: time.Time{},
			IsHammy:   true,
		},
		HeadRepoOwner: &types.ActionsAbuseUser{
			ID:        "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
			Name:      "github",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: time.Time{},
			IsHammy:   true,
		},
		BillingPlanOwner: &types.ActionsAbuseUser{
			ID:        "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
			Name:      "github",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: time.Time{},
			IsHammy:   true,
		},
		TargetRepository: &types.ActionsAbuseRepository{
			ID:         "MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM",
			DatabaseID: 1,
			NWO:        "github/launch",
			Private:    false,
			CreatedAt:  time.Time{},
		},
		HeadRepository: &types.ActionsAbuseRepository{
			ID:         "MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM",
			DatabaseID: 2,
			NWO:        "github/launch",
			Private:    false,
			CreatedAt:  time.Time{},
		},
	}
	mp := &BuildPayload{
		Root: RootPayload{
			PlanID: "b6a3d22a-00ae-11ea-8a8c-9d4669c45354",
			Configuration: rootPayloadConfig{
				MainFilePath: ".github/workflows/main.yml",
				RootWorkflow: rootWorkflow{
					FilePath:           ".github/workflows/main.yml",
					Ref:                "refs/heads/main",
					SHA:                "abcdefg",
					Repository:         "github/sourceRepo",
					RepositoryID:       types.GlobalID("source-repo-global-id"),
					IsRequiredWorkflow: false,
				},
				Callbacks: rootPayloadCallbacks{
					JobStatusURL:        "https://example.com/job-status",
					RunStatusURL:        "https://example.com/run-status",
					GateStatusURL:       "https://example.com/gate-status",
					EnvironmentURL:      "https://example.com/environment",
					PreJobURL:           "https://example.com/prejob",
					TokenRefreshURL:     "https://example.com/tokenrefresh",
					TokenRevokeURL:      "https://example.com/tokenrevoke",
					ActionResolutionURL: "https://example.com/resolveaction",
					ReceiverURL:         "https://example.com",
					ResultsReceiverURL:  "https://example.com/results",
					SignatureKey:        "signature-key",
				},
				ReferencedFiles: map[string]rootPayloadReferencedFile{
					"github/launch/.github/workflows/called.yml@main": {
						TenantID:             "tenant-id",
						Ref:                  "refs/heads/main",
						SHA:                  "abcdefg",
						Repository:           "github/launch",
						IsTrusted:            true,
						RepositoryID:         types.GlobalID("repo-global-id"),
						RepositoryDatabaseID: 1123,
						PlanOwnerID:          types.GlobalID("org-global-id"),
					},
				},
				OidcConfig: oidcConfig{
					SubClaimCustomizationTemplate: "test-template",
					CustomizeEnterpriseIssuer:     true,
				},
				IsLab: false,
			},
			Context: rootPayloadContext{
				Repository:                        "github/launch",
				RepositoryName:                    "launch",
				RepositoryOwner:                   "github",
				RepositoryID:                      "MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM=",
				RepositoryDatabaseID:              104793833,
				PrivateRepository:                 false,
				ForkedRepository:                  false,
				RepositoryVisibility:              "public",
				RepoSelfHostedRunnersDisabled:     true,
				Actor:                             "jclem",
				ActorID:                           "MDQ6VXNlcjE2NjMxMDQy",
				ActorDatabaseID:                   5,
				ForkedPullRequest:                 false,
				OwnerDatabaseID:                   10,
				OwnerCreatedAt:                    time.Time{},
				EnterpriseManagedBusinessID:       types.GlobalID("enterprise-global-id"),
				RepositoryURL:                     "git@github.com:github/launch.git",
				RunID:                             1,
				RunNumber:                         2,
				RunAttempt:                        123,
				Sha:                               "sha",
				Ref:                               "ref",
				RetentionDays:                     3,
				ActionsCacheSizeLimit:             15,
				OidcSubClaimCustomizationTemplate: "test-template",
				RepositoryTier:                    int64(types.RepositoryTier3),
				WorkflowPermissionsPolicy:         LimitedRead,

				BillingPlanOwner: rootPayloadBillingPlanOwner{
					ID:                     "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
					Name:                   "github",
					PlanSku:                "enterprise",
					Type:                   "Organization",
					TenantID:               "f39e98e3-8f30-448b-bce9-ecb6b16f8d54",
					TenantName:             "abc123",
					OrganizationID:         "", // Only needed when plan owner is a Business
					OrganizationTenantID:   "", // Only needed when plan owner is a Business
					OrganizationTenantName: "", // Only needed when plan owner is a Business
				},
				GitHubEventInfo: &gitHubEventInfo{
					AbuseInfo: &types.ActionsAbuseTriggerInfo{
						PartialAbuseTriggerInfo: pati,
						WorkflowExecutionID:     "aaaa",
						WorkflowFilePath:        ".github/workflows/main.yml",
						WorkflowRunID:           1,
						TargetRepositoryTier:    int(types.RepositoryTier3),
					},
					IsScheduled:   true,
					CustomerLabel: "top100",
				},
				ExtendedContext: rootPayloadExtendedContext{
					Actor:           "jclem",
					TriggeringActor: "aybabtme",
					Workflow:        "ci",
					EventName:       "pull_request",
					Event: map[string]any{
						"foo": "bar",
					},
					BaseRef:      "baseref",
					HeadRef:      "headref",
					ServerURL:    "http://github.localhost",
					APIURL:       "http://api.github.localhost",
					GraphQLURL:   "https://api.github.localhost/graphql",
					RefProtected: false,
					RefName:      "ref",
					RefType:      "branch",
					SecretSource: "Actions",
				},
				RunFeatureFlagsContext: map[string]bool{"feature1": true, "feature2": false},
				GitHubTenantSlug:       "staffship-01",
			},
			Secrets: map[string]string{
				"VERY_SECRET": "shhhh!",
			},
			Variables: map[string]string{
				"VARIABLE_ONE": "one",
			},
		},
		Files: []FilePayload{{
			Path:    ".github/workflows/main.yml",
			Content: []byte("Hello, world!"),
		}, {
			Path:    ".github/workflows/main-lab.yml",
			Content: []byte("Hello, world (from lab)!"),
		}},
	}

	payload, err := mp.ToMultipartPayload(func(mw *multipart.Writer) {
		err := mw.SetBoundary("BOUNDARY")
		require.NoError(t, err)
	})

	expectedConfiguration := `{"planId":"b6a3d22a-00ae-11ea-8a8c-9d4669c45354",
	"configuration":{"mainFilePath":".github/workflows/main.yml",
	"callbacks":{"jobStatusUrl":"https://example.com/job-status","runStatusUrl":"https://example.com/run-status","gateStatusUrl":"https://example.com/gate-status","environmentUrl":"https://example.com/environment","preJobUrl":"https://example.com/prejob","tokenRefreshUrl":"https://example.com/tokenrefresh","tokenRevokeUrl":"https://example.com/tokenrevoke","actionResolutionUrl":"https://example.com/resolveaction","receiverUrl":"https://example.com","signatureKey":"signature-key","resultsReceiverURL":"https://example.com/results"},
	"referencedFiles":{"github/launch/.github/workflows/called.yml@main":{"tenantId":"tenant-id","ref":"refs/heads/main","sha":"abcdefg","repository":"github/launch","isTrusted":true,"planOwnerId":"org-global-id","repositoryId":"repo-global-id","repositoryDatabaseId":1123}},
	"oidcConfig":{"subClaimCustomizationTemplate":"test-template","customizeEnterpriseIssuer":true},"mainWorkflow":{"filePath":".github/workflows/main.yml","ref":"refs/heads/main","sha":"abcdefg","repository":"github/sourceRepo","repositoryId":"source-repo-global-id","isRequiredWorkflow":false},"isLab":false},
	"context":{
		"repository":"github/launch","repositoryId":"MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM=","repositoryDatabaseId":104793833,"repositoryName":"launch","repositoryOwner":"github","repositoryUrl":"git@github.com:github/launch.git","privateRepository":false,"forkedRepository":false,"repositoryVisibility":"public","repoSelfHostedRunnersDisabled":true,"actor":"jclem","actorId":"MDQ6VXNlcjE2NjMxMDQy","actorDatabaseId":5,"forkedPullRequest":false,"forkedPullRequestEventContext":{},"ownerDatabaseID":10,"ownerCreatedAt":"0001-01-01T00:00:00Z","enterpriseManagedBusinessId":"enterprise-global-id","runId":1,"runNumber":2,"runAttempt":123,"sha":"sha","ref":"ref",
		"retentionDays":3,"artifactCacheSizeLimit":15,"repositoryTier":3,"oidcSubClaimCustomizationTemplate":"test-template","workflowPermissionsPolicy":"LimitedRead",
	"gitHubEventInfo":{"abuseInfo":{"workflowExecutionId":"aaaa","workflowFilePath":".github/workflows/main.yml","workflowRunId":1,"targetRepositoryTier":3,"triggerEvent":"push","triggerEventAction":"","actor":{"id":"MDQ6VXNlcjE2NjMxMDQy","name":"jclem","type":"User","plan":"free","createdAt":"0001-01-01T00:00:00Z","isHammy":true},"targetRepoOwner":{"id":"MDEyOk9yZ2FuaXphdGlvbjk5MTk=","name":"github","type":"Organization","plan":"enterprise","createdAt":"0001-01-01T00:00:00Z","isHammy":true},"headRepoOwner":{"id":"MDEyOk9yZ2FuaXphdGlvbjk5MTk=","name":"github","type":"Organization","plan":"enterprise","createdAt":"0001-01-01T00:00:00Z","isHammy":true},"billingPlanOwner":{"id":"MDEyOk9yZ2FuaXphdGlvbjk5MTk=","name":"github","type":"Organization","plan":"enterprise","createdAt":"0001-01-01T00:00:00Z","isHammy":true},"targetRepository":{"id":"MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM","databaseId":1,"private":false,"nwo":"github/launch","createdAt":"0001-01-01T00:00:00Z"},"headRepository":{"id":"MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM","databaseId":2,"private":false,"nwo":"github/launch","createdAt":"0001-01-01T00:00:00Z"}},"isScheduled":true,"customerLabel":"top100"},"billingPlanOwner":{"id":"MDEyOk9yZ2FuaXphdGlvbjk5MTk=","planSku":"enterprise","type":"Organization","name":"github","tenantId":"f39e98e3-8f30-448b-bce9-ecb6b16f8d54","tenantName":"abc123"},
	"extendedContext":{"actor":"jclem","triggering_actor":"aybabtme","workflow":"ci","head_ref":"headref","base_ref":"baseref","event_name":"pull_request","event":{"foo":"bar"},"server_url":"http://github.localhost","api_url":"http://api.github.localhost","graphql_url":"https://api.github.localhost/graphql","ref_name":"ref","ref_protected":false,"ref_type":"branch","secret_source":"Actions"},"runFeatureFlagsContext":{"feature1":true,"feature2":false},"gitHubTenantSlug":"staffship-01"},
	"secrets":{"VERY_SECRET":"shhhh!"},"variables":{"VARIABLE_ONE":"one"}}`

	expectedConfiguration = strings.ReplaceAll(expectedConfiguration, "\n", "")
	expectedConfiguration = strings.ReplaceAll(expectedConfiguration, "\t", "")

	require.NoError(t, err)
	assert.Equal(t, "--BOUNDARY\r\n"+
		"Content-Id: root\r\n"+
		"Content-Type: application/json\r\n\r\n"+

		expectedConfiguration+"\r\n"+
		"--BOUNDARY\r\n"+
		"Content-Description: file\r\n"+
		"Content-Id: .github/workflows/main.yml\r\n"+
		"Content-Type: text/plain\r\n\r\n"+

		"Hello, world!\r\n"+
		"--BOUNDARY\r\n"+
		"Content-Description: file\r\n"+
		"Content-Id: .github/workflows/main-lab.yml\r\n"+
		"Content-Type: text/plain\r\n\r\n"+

		"Hello, world (from lab)!\r\n"+
		"--BOUNDARY--\r\n",
		payload.Content.String())
}
