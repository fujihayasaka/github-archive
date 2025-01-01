package routing

import (
	"context"
	"fmt"
	"testing"

	"github.com/benbjohnson/clock"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"

	_ "github.com/go-sql-driver/mysql"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

type deleteSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func (suite *deleteSuite) TestDelete() {
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
		name          string
		userID        int64
		settings      []*MetaSetting
		fields        []CustomField
		expectedCount int
	}{
		{
			name:   "doesn't delete user settings when the custom field is different",
			userID: t.GetRef("2d-user2"),
			settings: []*MetaSetting{
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
			fields: []CustomField{
				{Name: "manual", Value: "true"},
			},
			expectedCount: 1,
		},
		{
			name:   "deletes user settings when the custom field matches",
			userID: t.GetRef("3d-user3"),
			settings: []*MetaSetting{
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
			fields: []CustomField{
				{Name: "manual", Value: "false"},
			},
			expectedCount: 0,
		},
		{
			name:   "does not delete user settings when empty custom fields are given",
			userID: t.GetRef("4d-user4"),
			settings: []*MetaSetting{
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
			fields:        []CustomField{},
			expectedCount: 1,
		},
		{
			name:   "deletes any user settings that match ALL custom field",
			userID: t.GetRef("5d-user5"),
			settings: []*MetaSetting{
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
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"}},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedCount: 0,
		},
		{
			name:   "does not delete user settings if they don't match ALL custom field",
			userID: t.GetRef("6d-user6"),
			settings: []*MetaSetting{
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
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedCount: 2,
		},
		{
			name:   "deletes user settings that match the custom field name when the custom field name matches and value is left empty",
			userID: t.GetRef("1d-user7"),
			settings: []*MetaSetting{
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
			fields: []CustomField{
				{Name: "manual"},
			},
			expectedCount: 0,
		},
	}
	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage := setup()
			// Create existing settings
			_, err := storage.BatchReplace(ctx, test.userID, test.settings, []CustomField{})
			suite.Require().NoError(err)

			// Delete settings
			err = storage.Delete(ctx, test.userID, test.fields)
			suite.Require().NoError(err)

			// Validate correct settings and internal settings created and replaced
			userSettings, _, err := storage.GetSettingsForUsers(ctx, []int64{test.userID}, []CustomField{}, pagination.NewStandardFirstPage())
			suite.Require().NoError(err)
			suite.Require().Len(userSettings, test.expectedCount)
		})
	}
}

func (suite *deleteSuite) TestDelete_Details() {
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

	settingsToDelete := []*MetaSetting{{
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

	suite.Run("correctly deletes fields", func() {
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

		// Create unrelated user settings
		unrelatedUserID := unrelatedUserSettings[0].UserID
		ids, err := storage.BatchReplace(ctx, unrelatedUserID, unrelatedUserSettings, []CustomField{})
		suite.Require().NoError(err)
		suite.Require().Len(ids, 1)

		userID := settingsToDelete[0].UserID
		suite.Require().NotEqual(userID, ids[0])

		// Create user settings
		fmt.Println(userID)
		ids, err = storage.BatchReplace(ctx, userID, settingsToDelete, []CustomField{})
		suite.Require().NoError(err)
		suite.Require().Len(ids, 1)

		// Check user settings have been created
		settings, _, err := storage.GetSettingsForUsers(ctx, []int64{userID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Len(settings, 1)

		err = storage.Delete(ctx, userID, []CustomField{{Name: "replace", Value: "true"}})
		suite.Require().NoError(err)

		// Validate unrelated user settings
		settings, _, err = storage.GetSettingsForUsers(ctx, []int64{unrelatedUserID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Equal(len(settings), len(unrelatedUserSettings))
		AssertMetaSettingIsSaved(suite.Require(), unrelatedUserSettings[0], settings[0])

		// Validate user settings
		settings, _, err = storage.GetSettingsForUsers(ctx, []int64{userID}, []CustomField{}, pagination.NewStandardFirstPage())
		suite.Require().NoError(err)
		suite.Require().Empty(settings)
	})
}

func TestDeleteSuite(t *testing.T) {
	testsuite.Run(t, new(deleteSuite))
}
