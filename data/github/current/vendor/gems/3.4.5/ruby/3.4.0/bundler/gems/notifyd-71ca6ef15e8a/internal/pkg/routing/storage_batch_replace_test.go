package routing

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"

	_ "github.com/go-sql-driver/mysql"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

type RoutingSettingsBatchReplaceDBTestSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func (suite *RoutingSettingsBatchReplaceDBTestSuite) TestBatchReplace() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func() Storage {
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)
		return storage
	}

	testCases := []struct {
		name                  string
		userID                int64
		existingSettings      []*MetaSetting
		settingsToCreate      []*MetaSetting
		replaceByCustomFields []CustomField
		expectedSettingsCount int
	}{
		{
			name:             "Create settings with no replacements",
			userID:           t.GetRef("1d-user1"),
			existingSettings: []*MetaSetting{},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("1d-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			replaceByCustomFields: []CustomField{},
			expectedSettingsCount: 1,
		},
		{
			name:   "doesn't replace a user's settings when the custom field is different",
			userID: t.GetRef("2d-user2"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("2d-user2"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("2d-user2"),
					Name:   "Test sub replace",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			replaceByCustomFields: []CustomField{
				{Name: "manual", Value: "true"},
			},
			expectedSettingsCount: 2,
		},
		{
			name:   "replaces user's settings when the custom field matches",
			userID: t.GetRef("3d-user3"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("3d-user3"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("3d-user3"),
					Name:   "Test sub replace",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "manual", Value: "false"}},
					},
				},
			},
			replaceByCustomFields: []CustomField{
				{Name: "manual", Value: "false"},
			},
			expectedSettingsCount: 1,
		},
		{
			name:   "does not replace a user's settings when empty custom fields are given",
			userID: t.GetRef("4d-user4"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("4d-user4"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("4d-user4"),
					Name:   "Test sub replace",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			replaceByCustomFields: []CustomField{},
			expectedSettingsCount: 2,
		},
		{
			name:   "replaces any user's settings that match ALL custom field",
			userID: t.GetRef("5d-user5"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
				{
					UserID: t.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: SettingDetails{

						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"}},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("5d-user5"),
					Name:   "Test sub replace",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			replaceByCustomFields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSettingsCount: 1,
		},
		{
			name:   "does not replace user's settings if they don't match ALL custom field",
			userID: t.GetRef("6d-user6"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
						},
					},
				},
				{
					UserID: t.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("6d-user6"),
					Name:   "Test sub replace",
					Details: SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			replaceByCustomFields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSettingsCount: 3,
		},
		{
			name:   "replaces user's settings that match the custom field name when the custom field name matches and value is left empty",
			userID: t.GetRef("1d-user7"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("1d-user7"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{
				{
					UserID: t.GetRef("1d-user7"),
					Name:   "Test sub replace",
					Details: SettingDetails{

						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: true},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "manual", Value: "false"}},
					},
				},
			},
			replaceByCustomFields: []CustomField{
				{Name: "manual"},
			},
			expectedSettingsCount: 1,
		},
		{
			name:   "deletes settings if no new ones are given",
			userID: t.GetRef("1d-user8"),
			existingSettings: []*MetaSetting{
				{
					UserID: t.GetRef("1d-user8"),
					Name:   "Test sub 1",
					Details: SettingDetails{

						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []SettingMatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			settingsToCreate: []*MetaSetting{},
			replaceByCustomFields: []CustomField{
				{Name: "manual"},
			},
			expectedSettingsCount: 0,
		},
	}
	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage := setup()
			// Create existing settings
			if len(test.existingSettings) > 0 {
				_, err := storage.BatchReplace(ctx, test.userID, test.existingSettings, []CustomField{})
				suite.Require().NoError(err)
			}

			// Replace settings
			createdSettingsIDs, err := storage.BatchReplace(ctx, test.userID, test.settingsToCreate, test.replaceByCustomFields)
			suite.Require().NoError(err)
			suite.Require().Equal(len(createdSettingsIDs), len(test.settingsToCreate))

			// Validate correct settings and internal settings created and replaced
			userSettings, _, err := storage.GetSettingsForUsers(ctx, []int64{test.userID}, []CustomField{}, pagination.NewStandardFirstPage())
			suite.Require().NoError(err)
			suite.Require().Len(userSettings, test.expectedSettingsCount)
		})
	}
}

func (suite *RoutingSettingsBatchReplaceDBTestSuite) TestBatchReplace_Details() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	unrelatedUserSettings := []*MetaSetting{{
		UserID: t.GetRef("1f-user1"),
		Name:   "Test sub 1",
		Details: SettingDetails{

			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []SettingFilter{
				{
					SubjectType: "issue",
					Trigger:     "created",
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
				{Name: "replace", Value: "true"},
			},
		},
	}}

	settingsToReplace := []*MetaSetting{{
		UserID: t.GetRef("1f-user2"),
		Name:   "Test sub 1",
		Details: SettingDetails{
			Channels: map[string]*matchengine_dto.Channel{
				"EMAIL": {Channel: "EMAIL", Enabled: true},
			},
			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []SettingFilter{
				{
					SubjectType: "issue",
					Trigger:     "created",
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
				{Name: "replace", Value: "true"},
			},
		},
	}}

	replacementSettings := []*MetaSetting{{
		UserID: t.GetRef("1f-user2"),
		Name:   "Test sub 1",
		Details: SettingDetails{
			Channels: map[string]*matchengine_dto.Channel{
				"EMAIL": {Channel: "EMAIL", Enabled: true},
			},
			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []SettingFilter{
				{
					SubjectType: "pull_request",
					Trigger:     "updated",
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "2", MatchRule: "list"},
						{Attribute: "body", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
			},
		},
	}}

	suite.Run("correctly replaces fields", func() {
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)

		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)

		unrelatedUserID := unrelatedUserSettings[0].UserID
		createdUnrelatedUserSettingsIDs, err := storage.BatchReplace(ctx, unrelatedUserID, unrelatedUserSettings, []CustomField{})
		suite.Require().NoError(err)
		suite.Require().Len(createdUnrelatedUserSettingsIDs, 1)

		settingsToReplaceUserIDs := settingsToReplace[0].UserID
		suite.Require().NotEqual(settingsToReplaceUserIDs, createdUnrelatedUserSettingsIDs[0])

		savedSettingsToReplaceIDs, err := storage.BatchReplace(ctx, settingsToReplaceUserIDs, settingsToReplace, []CustomField{})
		suite.Require().NoError(err)
		suite.Require().Len(savedSettingsToReplaceIDs, 1)
		savedSettingsToReplace, _, err := storage.GetSettingsForUsers(ctx, []int64{settingsToReplace[0].UserID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Len(savedSettingsToReplace, 1)

		replacementUserID := replacementSettings[0].UserID
		suite.Require().Equal(settingsToReplaceUserIDs, replacementUserID)
		createdSettingsIDs, err := storage.BatchReplace(ctx, replacementUserID, replacementSettings, []CustomField{{Name: "replace", Value: "true"}})
		suite.Require().NoError(err)
		suite.Require().Len(createdSettingsIDs, 1)

		// Validate unrelated user settings
		savedUnrelatedUserSettings, _, err := storage.GetSettingsForUsers(ctx, []int64{unrelatedUserID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Equal(len(savedUnrelatedUserSettings), len(unrelatedUserSettings))
		AssertMetaSettingIsSaved(suite.Require(), unrelatedUserSettings[0], savedUnrelatedUserSettings[0])

		// Validate user settings
		savedSettings, _, err := storage.GetSettingsForUsers(ctx, []int64{replacementUserID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Equal(len(savedSettings), len(replacementSettings))
		AssertMetaSettingIsSaved(suite.Require(), savedSettings[0], replacementSettings[0])
	})
}

func TestRoutingSettingsBatchReplaceDBTestSuite(t *testing.T) {
	testsuite.Run(t, new(RoutingSettingsBatchReplaceDBTestSuite))
}
