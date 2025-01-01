package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestRepositoryConversion(t *testing.T) {
	r := &Repository{
		URL:     "http://github.test/test-org/test-repo",
		Private: true,
	}

	expected := &v1.Repository{
		ResourceId: r.URL,
		IsPrivate:  true,
	}

	v1r, err := r.ToV1Repository()
	require.NoError(t, err)
	require.Equal(t, expected, v1r)

	r.Private = false
	expected = &v1.Repository{
		ResourceId: r.URL,
		IsPrivate:  false,
	}

	v1r, err = r.ToV1Repository()
	require.NoError(t, err)
	require.Equal(t, expected, v1r)
}

func boolPtr(b bool) *bool {
	return &b
}
func TestToRepositorySettings(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	r := &Repository{
		URL:           "http://github.test/test-org/test-repo",
		Description:   "Test repository",
		DefaultBranch: "main",
		HasWiki:       true,
		HasIssues:     true,
		HasDownloads:  true,
		SecurityAndAnalysis: SecurityAndAnalysis{
			DependencyGraph:             true,
			VulnerabilityAlerts:         true,
			VulnerabilityUpdates:        true,
			AdvancedSecurity:            true,
			TokenScanning:               true,
			TokenScanningPushProtection: true,
		},
		Autolinks: []*Autolink{
			{
				KeyPrefix:      "JIRA",
				URLTemplate:    "idk",
				IsAlphanumeric: true,
			},
		},
		Webhooks: []*Webhook{
			{
				PayloadURL:            "abc",
				ContentType:           "foo",
				EventTypes:            []string{"abc"},
				EnableSSLVerification: true,
				Active:                true,
			},
		},
		RepositoryTopics: []*RepositoryTopic{
			{
				TopicName: "abc",
				TopicURL:  "some-url",
				State:     "state",
				Creator:   "monalisa",
				CreatedAt: someTime,
				UpdatedAt: someTime,
			},
		},
		GeneralSettings: &GeneralSettings{
			Template:          boolPtr(true),
			AllowForking:      boolPtr(true),
			Sponsorships:      boolPtr(false),
			Discussions:       boolPtr(true),
			MergeCommit:       boolPtr(false),
			SquashMerge:       boolPtr(true),
			RebaseMerge:       boolPtr(true),
			AutoMerge:         boolPtr(false),
			DeleteBranchHeads: boolPtr(true),
			UpdateBranch:      boolPtr(false),
			GitLFSInArchives:  boolPtr(true),
			Projects:          boolPtr(true),
		},
		Page: &Page{
			Source:        "master",
			SourceRefName: "refs/heads/master",
			SourceSubDir:  "/docs",
			IsPublic:      true,
			BuildType:     "static",
		},
	}

	expected := &v1.InitialRepositorySettings{
		ResourceId:                     "repositorysettings-http://github.test/test-org/test-repo",
		RepositoryResourceId:           r.URL,
		Description:                    "Test repository",
		DefaultBranch:                  "main",
		HasWiki:                        true,
		HasIssues:                      true,
		HasDownloads:                   true,
		HasDependencyGraph:             true,
		HasVulnerabilityAlerts:         true,
		HasVulnerabilityUpdates:        true,
		HasAdvancedSecurity:            true,
		HasTokenScanning:               true,
		HasTokenScanningPushProtection: true,
		GeneralRepositorySettings: &v1.GeneralRepositorySettings{
			IsTemplate:           &wrapperspb.BoolValue{Value: true},
			HasAllowForking:      &wrapperspb.BoolValue{Value: true},
			HasSponsorships:      &wrapperspb.BoolValue{Value: false},
			HasDiscussions:       &wrapperspb.BoolValue{Value: true},
			HasMergeCommit:       &wrapperspb.BoolValue{Value: false},
			HasSquashMerge:       &wrapperspb.BoolValue{Value: true},
			HasRebaseMerge:       &wrapperspb.BoolValue{Value: true},
			HasAutoMerge:         &wrapperspb.BoolValue{Value: false},
			HasDeleteBranchHeads: &wrapperspb.BoolValue{Value: true},
			HasUpdateBranch:      &wrapperspb.BoolValue{Value: false},
			HasGitLfsInArchives:  &wrapperspb.BoolValue{Value: true},
			HasProjects:          &wrapperspb.BoolValue{Value: true},
		},
		Page: &v1.Page{
			Source:        "master",
			SourceRefName: "refs/heads/master",
			SourceSubdir:  "/docs",
			IsPublic:      true,
			BuildType:     "static",
		},
		Webhooks: []*v1.Webhook{
			{
				PayloadUrl:            r.Webhooks[0].PayloadURL,
				ContentType:           r.Webhooks[0].ContentType,
				Active:                r.Webhooks[0].Active,
				EnableSslVerification: r.Webhooks[0].EnableSSLVerification,
				EventTypes:            r.Webhooks[0].EventTypes,
			},
		},
		Autolinks: []*v1.Autolink{
			{
				KeyPrefix:      r.Autolinks[0].KeyPrefix,
				UrlTemplate:    r.Autolinks[0].URLTemplate,
				IsAlphanumeric: r.Autolinks[0].IsAlphanumeric,
			},
		},
		RepositoryTopics: []*v1.RepositoryTopic{
			{
				TopicUrl:          r.RepositoryTopics[0].TopicURL,
				TopicName:         r.RepositoryTopics[0].TopicName,
				State:             r.RepositoryTopics[0].State,
				CreatorResourceId: r.RepositoryTopics[0].Creator,
				CreatedAt:         toTimestamp(someTime),
				UpdatedAt:         toTimestamp(someTime),
			},
		},
	}

	v1r := r.ToV1InitialRepositorySettings()
	require.Equal(t, expected, v1r)
	t.Run("GeneralSettingsNil-Able", func(t *testing.T) {
		r.GeneralSettings = &GeneralSettings{
			Template:          nil,
			AllowForking:      boolPtr(true),
			Sponsorships:      nil,
			Discussions:       boolPtr(true),
			MergeCommit:       nil,
			SquashMerge:       nil,
			RebaseMerge:       boolPtr(true),
			AutoMerge:         nil,
			DeleteBranchHeads: nil,
			UpdateBranch:      boolPtr(false),
			GitLFSInArchives:  nil,
			Projects:          boolPtr(true),
		}
		expected.GeneralRepositorySettings = &v1.GeneralRepositorySettings{
			IsTemplate:           nil,
			HasAllowForking:      &wrapperspb.BoolValue{Value: true},
			HasSponsorships:      nil,
			HasDiscussions:       &wrapperspb.BoolValue{Value: true},
			HasMergeCommit:       nil,
			HasSquashMerge:       nil,
			HasRebaseMerge:       &wrapperspb.BoolValue{Value: true},
			HasAutoMerge:         nil,
			HasDeleteBranchHeads: nil,
			HasUpdateBranch:      &wrapperspb.BoolValue{Value: false},
			HasGitLfsInArchives:  nil,
			HasProjects:          &wrapperspb.BoolValue{Value: true},
		}
		v1r = r.ToV1InitialRepositorySettings()
		require.Equal(t, expected, v1r)
	})
}

func TestToActionsSettings(t *testing.T) {
	tests := []struct {
		name               string
		repo               *Repository
		expectedPermission v1.ActionsPermissionType
		expectedResourceID string
	}{
		{
			name: "ActionsDisabledIsInvalid",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					ActionsDisabled:               true,
					AllowsAllActions:              false,
					AllowsLocalActionsOnly:        false,
					AllowsSpecificActionsPatterns: false,
					Patterns:                      []string{},
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INVALID,
		},
		{
			name: "ActionsPermissionType_AllEnabled",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					AllowsAllActions: true,
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_ALL_ENABLED,
		},
		{
			name: "ActionsPermissionType_LocalEnabled",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					AllowsLocalActionsOnly: true,
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED,
		},
		{
			name: "ActionsPermissionType_SpecificEnabled_Patterns",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					Patterns: []string{"a"},
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED,
		},
		{
			name: "ActionsPermissionType_SpecificEnabled_GitHubOwned",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					AllowsGitHubOwnedActions: true,
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED,
		},
		{
			name: "ActionsPermissionType_SpecificEnabled_Verified",
			repo: &Repository{
				ActionsGeneralSettings: &ActionsGeneralSettings{
					AllowsVerifiedActions: true,
				},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED,
		},
		{
			name: "ActionsSettingsResourceId",
			repo: &Repository{
				URL:                    "http://github.dev/repo",
				ActionsGeneralSettings: &ActionsGeneralSettings{},
			},
			expectedPermission: v1.ActionsPermissionType_ACTIONS_PERMISSION_TYPE_INVALID,
			expectedResourceID: "actionssettings-http://github.dev/repo",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := tt.repo.ToV1InitialActionsSettings()

			// Verify ActionsPermissions
			require.Equal(t, tt.expectedPermission, settings.ActionsPermissions)

			// Verify ResourceId if expected
			if tt.expectedResourceID != "" {
				require.Equal(t, tt.expectedResourceID, settings.ResourceId)
			}
		})
	}
}

func TestPrepareRepositoryLabelsBatches(t *testing.T) {
	testCases := []struct {
		name            string
		labels          []*v1.RepositoryLabel
		repoID          string
		batchSize       int
		expectedBatches int
		expectedErr     bool
	}{
		{
			name:            "Multiple batches",
			labels:          []*v1.RepositoryLabel{{}, {}, {}, {}, {}},
			repoID:          "repo",
			batchSize:       2,
			expectedBatches: 3,
		},
		{
			name:            "Empty labels list",
			labels:          []*v1.RepositoryLabel{},
			repoID:          "repo",
			batchSize:       2,
			expectedBatches: 0,
		},
		{
			name:            "Batch size larger than labels",
			labels:          []*v1.RepositoryLabel{{}, {}},
			repoID:          "repo",
			batchSize:       10,
			expectedBatches: 1, // All labels in one batch
		},
		{
			name:            "Invalid batch size (zero)",
			labels:          []*v1.RepositoryLabel{{}, {}},
			repoID:          "repo",
			batchSize:       0,
			expectedBatches: 0,
			expectedErr:     true,
		},
		{
			name:            "Exact batch size",
			labels:          []*v1.RepositoryLabel{{}, {}, {}},
			repoID:          "repo",
			batchSize:       3,
			expectedBatches: 1, // 3 labels, 3 per batch = 1 batch
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			batches, err := prepareRepositoryLabelsBatches(tc.repoID, tc.labels, tc.batchSize)
			require.Equal(t, tc.expectedErr, err != nil)
			assert.Equal(t, tc.expectedBatches, len(batches))
			for _, b := range batches {
				assert.Contains(t, b.ResourceId, tc.repoID)
			}
		})
	}
}
