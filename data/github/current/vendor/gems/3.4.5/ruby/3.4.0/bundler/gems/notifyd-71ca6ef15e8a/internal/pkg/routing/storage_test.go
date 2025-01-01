package routing

import (
	"context"
	"encoding/base64"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Masterminds/squirrel"
	clockpkg "github.com/benbjohnson/clock"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
)

type storageSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func TestStorageSuite(t *testing.T) {
	testsuite.Run(t, new(storageSuite))
}

func (suite *storageSuite) TestStorageSuite_Create() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func(clock clockpkg.Clock) *storage {
		suite.T().Helper()

		// The MetaID is hardcoded in the fixtures in order to be able to assert the proper
		// data has been saved. For now we need to truncate the tables
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		store := NewStorage(clock, logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	testCases := []struct {
		name                    string
		metaRoutingSetting      *MetaSetting
		queryByUserID           int64
		expectedRoutingSettings []*Setting
	}{
		{
			name:          "create meta routing setting with routing settings and corresponding match rules and channels",
			queryByUserID: t.GetRef("1c-user1"),
			metaRoutingSetting: &MetaSetting{
				UserID: t.GetRef("1c-user1"),
				Name:   "Test sub 1",
				Details: SettingDetails{
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
					Topics: []Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					Filters: []SettingFilter{
						{
							Reason:      "subscribed",
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
				},
			},
			expectedRoutingSettings: []*Setting{
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "issue",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "pull_request",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "issue",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "pull_request",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
			},
		},
		{
			name:          "creates meta routing setting without routing setting and matching rules",
			queryByUserID: t.GetRef("3c-user1"),
			metaRoutingSetting: &MetaSetting{
				UserID: t.GetRef("3c-user1"),
				Name:   "Test sub 1",
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
				},
			},
			expectedRoutingSettings: []*Setting{
				{
					UserID:      t.GetRef("3c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "any",
					Trigger:     "any",
					MetaID:      1,
				},
				{
					UserID:      t.GetRef("3c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "any",
					Trigger:     "any",
					MetaID:      1,
				},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			setting := *test.metaRoutingSetting

			clock := clockpkg.NewMock()
			checkPoint := time.Now().UTC().Truncate(time.Second)
			clock.Set(checkPoint)

			storage := setup(clock)

			createdMetaRoutingSetting, err := storage.Create(ctx, &setting)
			suite.Require().NoError(err)
			suite.Require().NotNil(createdMetaRoutingSetting)

			fetchedMetaRoutingSetting, err := storage.getMetaRoutingSettingByID(ctx, createdMetaRoutingSetting.ID)
			suite.Require().NoError(err)
			suite.Require().Positive(fetchedMetaRoutingSetting.ID)
			suite.Require().Equal(checkPoint, fetchedMetaRoutingSetting.UpdatedAt, "Updated at should be eq to checkpoint")
			suite.Require().Equal(checkPoint, fetchedMetaRoutingSetting.CreatedAt, "Created at should be eq to checkpoint")

			savedRoutingSettings, err := storage.getRoutingSettings(ctx, test.queryByUserID)
			suite.Require().NoError(err)
			suite.Require().Len(savedRoutingSettings, len(test.expectedRoutingSettings))

			AssertMetaSettingIsSaved(suite.Require(), fetchedMetaRoutingSetting, &setting)
			AssertSettingsAreSaved(suite.Require(), test.expectedRoutingSettings, savedRoutingSettings)
		})
	}
}

func (suite *storageSuite) TestStorage_BatchCreateAndDelete_Create() {
	// This test checks the details of a Batch Create, the `toCreate` field in this test is only used with a single field

	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func(clock clockpkg.Clock) *storage {
		suite.T().Helper()

		// The MetaID is hardcoded in the fixtures in order to be able to assert the proper
		// data has been saved. For now we need to truncate the tables
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		store := NewStorage(clock, logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	testCases := []struct {
		name                    string
		toCreate                MetaSetting
		expectedRoutingSettings []*Setting
	}{
		{
			name: "create meta routing setting with routing settings and corresponding match rules and channels",
			toCreate: MetaSetting{
				UserID: t.GetRef("1c-user1"),
				Name:   "Test sub 1",
				Details: SettingDetails{
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
					Topics: []Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					Filters: []SettingFilter{
						{
							Reason:      "subscribed",
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
						{
							Name:  "delivery_group",
							Value: "CI Activity",
						},
					},
				},
			},
			expectedRoutingSettings: []*Setting{
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "issue",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "pull_request",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "issue",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
				{
					UserID:      t.GetRef("1c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "pull_request",
					Trigger:     "created",
					MetaID:      1,
					MatchRules: []SettingMatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
					Channels: ToChannelsMap(map[string]bool{"EMAIL": true, "PUSH": true}),
				},
			},
		},
		{
			name: "creates meta routing setting without routing setting and matching rules",
			toCreate: MetaSetting{
				UserID: t.GetRef("3c-user1"),
				Name:   "Test sub 1",
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
				},
			},
			expectedRoutingSettings: []*Setting{
				{
					UserID:      t.GetRef("3c-user1"),
					TopicType:   "repository",
					TopicValue:  "123",
					SubjectType: "any",
					Trigger:     "any",
					MetaID:      1,
				},
				{
					UserID:      t.GetRef("3c-user1"),
					TopicType:   "repository",
					TopicValue:  "456",
					SubjectType: "any",
					Trigger:     "any",
					MetaID:      1,
				},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			setting := test.toCreate

			clock := clockpkg.NewMock()
			checkPoint := time.Now().UTC().Truncate(time.Second)
			clock.Set(checkPoint)

			storage := setup(clock)

			createdMetaRoutingSettings, err := storage.BatchCreateAndDelete(ctx, []*MetaSetting{&setting}, []int64{})
			suite.Require().NoError(err)
			suite.Require().Len(createdMetaRoutingSettings, 1)
			AssertMetaSettingIsSaved(suite.Require(), createdMetaRoutingSettings[0], &setting)

			fetchedMetaRoutingSetting, err := storage.getMetaRoutingSettingByID(ctx, createdMetaRoutingSettings[0].ID)
			suite.Require().NoError(err)
			suite.Require().Positive(fetchedMetaRoutingSetting.ID)
			suite.Require().Equal(checkPoint, fetchedMetaRoutingSetting.UpdatedAt, "Updated at should be eq to checkpoint")
			suite.Require().Equal(checkPoint, fetchedMetaRoutingSetting.CreatedAt, "Created at should be eq to checkpoint")

			savedRoutingSettings, err := storage.getRoutingSettings(ctx, setting.UserID)
			suite.Require().NoError(err)
			suite.Require().Len(savedRoutingSettings, len(test.expectedRoutingSettings))

			AssertSettingsAreSaved(suite.Require(), test.expectedRoutingSettings, savedRoutingSettings)
			AssertMetaSettingIsSaved(suite.Require(), fetchedMetaRoutingSetting, &setting)
		})
	}
}

func (suite *storageSuite) TestStorage_BatchCreateAndDelete_Delete() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func(clock clockpkg.Clock) *storage {
		suite.T().Helper()

		// The MetaID is hardcoded in the fixtures in order to be able to assert the proper
		// data has been saved. For now we need to truncate the tables
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		store := NewStorage(clock, logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	testCases := []struct {
		name                  string
		existingSetting       []*MetaSetting
		usersSettingsToDelete []int64
	}{
		{
			name: "delete multiple routing settings",
			existingSetting: []*MetaSetting{
				{
					UserID: t.GetRef("1c-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Filters: []SettingFilter{
							{Reason: "approval_requested"},
						},
						CustomFields: []CustomField{
							{
								Name:  "delivery_group",
								Value: "user 1",
							},
						},
					},
				},
				{
					UserID: t.GetRef("2c-user2"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Filters: []SettingFilter{
							{Reason: "approval_requested"},
						},
						CustomFields: []CustomField{
							{
								Name:  "delivery_group",
								Value: "user 2",
							},
						},
					},
				},
				{
					UserID: t.GetRef("3c-user2"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Filters: []SettingFilter{
							{Reason: "approval_requested"},
						},
						CustomFields: []CustomField{
							{
								Name:  "delivery_group",
								Value: "user 3",
							},
						},
					},
				},
			},
			usersSettingsToDelete: []int64{
				t.GetRef("1c-user1"),
				t.GetRef("2c-user2"),
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage := setup(clockpkg.NewMock())

			createdMetaRoutingSettings, err := storage.BatchCreateAndDelete(ctx, test.existingSetting, []int64{})
			suite.Require().NoError(err)
			suite.Require().NotEmpty(createdMetaRoutingSettings)
			suite.Require().Equal(len(test.existingSetting), len(createdMetaRoutingSettings))

			settingsToDelete := make([]MetaSetting, 0)
			settingsToKeep := make([]MetaSetting, 0)

			for _, createdMetaRoutingSetting := range createdMetaRoutingSettings {
				var found bool
				for _, userID := range test.usersSettingsToDelete {
					if createdMetaRoutingSetting.UserID == userID {
						found = true
					}
				}

				if found {
					settingsToDelete = append(settingsToDelete, *createdMetaRoutingSetting)
				} else {
					settingsToKeep = append(settingsToKeep, *createdMetaRoutingSetting)
				}
			}

			metaIDsToDelete := make([]int64, 0)
			for _, settings := range settingsToDelete {
				metaIDsToDelete = append(metaIDsToDelete, settings.ID)
			}

			routingSettingsIDsToDelete, err := storage.getRoutingIDsByMetaRoutingSettingIDs(ctx, metaIDsToDelete)
			suite.Require().NoError(err)

			newCreatedMetaRoutingSettings, err := storage.BatchCreateAndDelete(ctx, []*MetaSetting{}, metaIDsToDelete)
			suite.Require().NoError(err)
			suite.Require().Empty(newCreatedMetaRoutingSettings)

			channels, err := storage.getChannelsByRoutingSettingIDs(ctx, routingSettingsIDsToDelete)
			suite.Require().NoError(err)
			suite.Require().Empty(channels)

			matchRules, err := storage.getMatchRulesByRoutingSettingIDs(ctx, routingSettingsIDsToDelete)
			suite.Require().NoError(err)
			suite.Require().Empty(matchRules)

			for _, metaRoutingSettings := range settingsToDelete {
				fetchedMetaRoutingSetting, err := storage.getMetaRoutingSettingByID(ctx, metaRoutingSettings.ID)
				suite.Require().NoError(err)
				suite.Require().Equal(int64(0), fetchedMetaRoutingSetting.ID)
				suite.Require().Equal(int64(0), fetchedMetaRoutingSetting.UserID)

				savedRoutingSettings, err := storage.getRoutingSettings(ctx, metaRoutingSettings.UserID)
				suite.Require().NoError(err)
				suite.Require().Empty(savedRoutingSettings)

				suite.assertEmptyCustomFields(metaRoutingSettings.ID)
			}

			// Check that meta routing settings for other users were not deleted
			for _, settings := range settingsToKeep {
				fetchedMetaRoutingSetting, err := storage.getMetaRoutingSettingByID(ctx, settings.ID)
				suite.Require().NoError(err)
				suite.Require().NotEqual(int64(0), fetchedMetaRoutingSetting.UserID)
				settingsToCheck := settings // prevent implicit memory aliasing in for loop.
				AssertMetaSettingIsSaved(suite.Require(), &settingsToCheck, fetchedMetaRoutingSetting)
			}
		})
	}
}

func (suite *storageSuite) TestStorage_buildMatchingRoutingSettingsQuery() {
	createExpectedQuery := func(dynamicPart string) string {
		return strings.ReplaceAll(`SELECT
		 pre_selected_query.id AS ref_id,
		 pre_selected_query.user_id,
		 pre_selected_query.reason,
		 routing_setting_match_rules.attribute,
		 routing_setting_match_rules.value, `+
			"routing_setting_match_rules.`match` AS match_rule FROM "+
			"(SELECT routing_settings.id, user_id, reason FROM routing_settings "+
			"	LEFT JOIN routing_setting_match_rules ON routing_settings.id = `routing_setting_match_rules`.routing_setting_id "+
			`	WHERE routing_settings.user_id IN (?,?,?) AND (routing_settings.reason = ? OR routing_settings.reason IN (?,?)) AND ((routing_settings.topic_type = ? AND routing_settings.topic_value = ?) OR (routing_settings.topic_type = ? AND routing_settings.topic_value = ?)) AND
		 		((routing_settings.subject_type = ? AND routing_settings.trigger = ?) OR
					(routing_settings.subject_type = ? AND routing_settings.trigger = ?) OR
					(routing_settings.subject_type = ? AND routing_settings.trigger = ?)) AND `+
			dynamicPart+
			") AS pre_selected_query LEFT JOIN routing_setting_match_rules ON pre_selected_query.id = `routing_setting_match_rules`.routing_setting_id",
			"\n", "")
	}

	tests := map[string]struct {
		topics             []notify.Topic
		subject            string
		trigger            string
		attributes         []notify.Attribute
		expectedQuery      string
		expectedParameters []interface{}
	}{
		"get routing settings without attributes": {
			topics: []notify.Topic{{
				Type:  "repository",
				Value: "123",
			}},
			subject:       "issue",
			trigger:       "labeled",
			expectedQuery: createExpectedQuery("(routing_setting_match_rules.routing_setting_id IS NULL)"),
			expectedParameters: []interface{}{
				int64(1), int64(2), int64(3),
				"any",
				"subscribed",
				"ci_activity",
				"any",
				"any",
				"repository",
				"123",
				"any",
				"any",
				"issue",
				"any",
				"issue",
				"labeled",
			},
		},
		"get routing settings with single reason": {
			topics: []notify.Topic{{
				Type:  "repository",
				Value: "123",
			}},
			subject:       "issue",
			trigger:       "labeled",
			expectedQuery: createExpectedQuery("(routing_setting_match_rules.routing_setting_id IS NULL)"),
			expectedParameters: []interface{}{
				int64(1), int64(2), int64(3),
				"any",
				"subscribed",
				"ci_activity",
				"any",
				"any",
				"repository",
				"123",
				"any",
				"any",
				"issue",
				"any",
				"issue",
				"labeled",
			},
		},

		"get routing settings with one attribute": {
			topics: []notify.Topic{{
				Type:  "repository",
				Value: "123",
			}},
			subject: "issue",
			trigger: "labeled",
			attributes: []notify.Attribute{
				{Name: "author_id", Value: "123"},
			},
			expectedQuery: createExpectedQuery("(routing_setting_match_rules.routing_setting_id IS NULL OR (routing_setting_match_rules.attribute = ? AND (routing_setting_match_rules.value = ? OR routing_setting_match_rules.match <> ?)))"),
			expectedParameters: []interface{}{
				int64(1), int64(2), int64(3),
				"any",
				"subscribed",
				"ci_activity",
				"any",
				"any",
				"repository",
				"123",
				"any",
				"any",
				"issue",
				"any",
				"issue",
				"labeled",
				"author_id",
				"123",
				"eq",
			},
		},
		"get routing settings with multiple attributes": {
			topics: []notify.Topic{{
				Type:  "repository",
				Value: "123",
			}},
			subject: "issue",
			trigger: "labeled",
			attributes: []notify.Attribute{
				{Name: "author_id", Value: "123"},
				{Name: "added_label", Value: "456"},
			},
			expectedQuery: createExpectedQuery("(routing_setting_match_rules.routing_setting_id IS NULL OR (routing_setting_match_rules.attribute = ? AND (routing_setting_match_rules.value = ? OR routing_setting_match_rules.match <> ?)) OR (routing_setting_match_rules.attribute = ? AND (routing_setting_match_rules.value = ? OR routing_setting_match_rules.match <> ?)))"),

			expectedParameters: []interface{}{
				int64(1), int64(2), int64(3),
				"any",
				"subscribed",
				"ci_activity",
				"any",
				"any",
				"repository",
				"123",
				"any",
				"any",
				"issue",
				"any",
				"issue",
				"labeled",
				"author_id",
				"123",
				"eq",
				"added_label",
				"456",
				"eq",
			},
		},
	}

	for name, tc := range tests {
		suite.Run(name, func() {
			userIDs := []int64{1, 2, 3}
			reasons := []string{"subscribed", "ci_activity"}
			query, params, err := buildMatchingRoutingSettingsQuery(userIDs, reasons, tc.topics, tc.subject, tc.trigger, tc.attributes...)
			suite.Require().NoError(err)
			// prepare queries for comparison (remove all extra whitespaces and breaks)
			expectedQuery := strings.ReplaceAll(tc.expectedQuery, "\r\n", " ")
			expectedQuery = strings.ReplaceAll(expectedQuery, "\n", " ")

			query = strings.ReplaceAll(query, "\n", " ")

			space := regexp.MustCompile(`\s+`)
			expectedQuery = space.ReplaceAllString(expectedQuery, " ")
			query = space.ReplaceAllString(query, " ")

			suite.Require().Equal(expectedQuery, query)
			suite.Require().Equal(tc.expectedParameters, params)
		})
	}
}

func (suite *storageSuite) TestStorage_GetMatchingEntries() {
	ctx := context.Background()
	db := suite.DB()
	clock := clockpkg.NewMock()

	setup := func() Storage {
		suite.T().Helper()

		// The MetaID is hardcoded in the fixtures in order to be able to assert the proper
		// data has been saved. For now we need to truncate the tables
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		return NewStorage(clock, logs.NullTelem, db)
	}

	metaRoutingSettingsInDB := []*MetaSetting{
		// subscription with no event filter
		{
			UserID: 1,
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
			},
		},
		// subscriptions with only subject filter
		{
			UserID: 2,
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []SettingFilter{
					{SubjectType: "Issue", Reason: "subscribed"},
				},
			},
		},
		{
			UserID: 3,
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []SettingFilter{
					{SubjectType: "PullRequest", Reason: "subscribed"},
				},
			},
		},
		// subscription with subject and trigger filter
		{
			UserID: 4,
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []SettingFilter{
					{SubjectType: "Issue", Trigger: "create", Reason: "subscribed"},
				},
			},
		},
		// subscription with subject, trigger and match rule filter
		{
			UserID: 5,
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []SettingFilter{
					{
						SubjectType: "Issue",
						Trigger:     "create",
						Reason:      "subscribed",
						MatchRules: []SettingMatchRule{
							{Attribute: "has_label", Value: "1", MatchRule: "eq"},
						},
					},
					{
						SubjectType: "Issue",
						Trigger:     "labeled",
						Reason:      "subscribed",
						MatchRules: []SettingMatchRule{
							{Attribute: "added_label", Value: "1", MatchRule: "eq"},
							{Attribute: "title", Value: "subscription", MatchRule: "contains"},
						},
					},
				},
			},
		},
	}

	testCases := []struct {
		name                       string
		dbMetaRoutingSettings      []*MetaSetting
		userID                     int64
		potentialRecipients        []int64
		potentialRecipientsReasons []string
		msgMatchFields             notify.MessageMatchFields
		expectedMatchedEntries     []*matchengine.MatchedEntry
	}{
		{
			name:                  "fetches all the routing settings with given subject type and trigger for given topic",
			userID:                1,
			dbMetaRoutingSettings: metaRoutingSettingsInDB,
			potentialRecipients:   []int64{1, 2, 3, 4, 5},
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "create",
			},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "any", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 4, RefID: 4, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
			},
		},
		{
			name:   "fetches all the routing settings with given reason for global topic based on CheckSuite use-case",
			userID: 1,
			dbMetaRoutingSettings: []*MetaSetting{
				{
					UserID: 1,
					Name:   "Global setting for CI activities - CheckSuite",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "any", Value: "any"},
						},
						Filters: []SettingFilter{
							{Reason: "ci_activity"},
						},
					},
				},
			},
			potentialRecipients:        []int64{1, 2},
			potentialRecipientsReasons: []string{"subscribed", "ci_activity"},
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "CheckSuite",
				Trigger:     "any",
			},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "ci_activity", Attribute: "", Value: "", MatchRule: ""},
			},
		},
		{
			name:   "fetches all the routing settings with given reason for global topic based on WorkflowRun use-case",
			userID: 1,
			dbMetaRoutingSettings: []*MetaSetting{
				{
					UserID: 1,
					Name:   "Global setting for CI activities - Workflow Run Approval",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "any", Value: "any"},
						},
						Filters: []SettingFilter{
							{Reason: "approval_requested"},
						},
					},
				},
			},
			potentialRecipients:        []int64{1, 2},
			potentialRecipientsReasons: []string{"subscribed", "approval_requested"},
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Actions::WorkflowRun",
				Trigger:     "any",
				Attributes: []notify.Attribute{
					{Name: "failed", Value: "true"},
				},
			},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "approval_requested", Attribute: "", Value: "", MatchRule: ""},
			},
		},
		{
			name:                  "fetches all the routing settings match rules with given subject type, trigger and subscription attributes",
			userID:                1,
			dbMetaRoutingSettings: metaRoutingSettingsInDB,
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "labeled",
				Attributes:  []notify.Attribute{{Name: "added_label", Value: "1"}},
			},
			potentialRecipients: []int64{1, 2, 3, 4, 5},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "any", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 5, RefID: 6, Reason: "subscribed", Attribute: "added_label", Value: "1", MatchRule: "eq"},
				{UserID: 5, RefID: 6, Reason: "subscribed", Attribute: "title", Value: "subscription", MatchRule: "contains"},
			},
		},
		{
			name:                  "fetches no routing settings if no potential recipients specified",
			userID:                1,
			dbMetaRoutingSettings: metaRoutingSettingsInDB,
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "labeled",
				Attributes:  []notify.Attribute{{Name: "added_label", Value: "1"}},
			},
			potentialRecipients:    []int64{},
			expectedMatchedEntries: []*matchengine.MatchedEntry{},
		},
		{
			name:                  "fetches routing settings match rules with given subject type, trigger and subscription attributes for matched potential recipients",
			userID:                1,
			dbMetaRoutingSettings: metaRoutingSettingsInDB,
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "labeled",
				Attributes:  []notify.Attribute{{Name: "added_label", Value: "1"}},
			},
			potentialRecipients: []int64{5},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 5, RefID: 6, Reason: "subscribed", Attribute: "added_label", Value: "1", MatchRule: "eq"},
				{UserID: 5, RefID: 6, Reason: "subscribed", Attribute: "title", Value: "subscription", MatchRule: "contains"},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			routingSettingsDB := setup()
			for _, metaRoutingSetting := range test.dbMetaRoutingSettings {
				_, err := routingSettingsDB.Create(ctx, metaRoutingSetting)
				suite.Require().NoError(err)
			}

			matchedEntries, err := routingSettingsDB.GetMatchingEntries(ctx, test.potentialRecipients, test.potentialRecipientsReasons, test.msgMatchFields)

			suite.Require().NoError(err)

			suite.Require().Len(matchedEntries, len(test.expectedMatchedEntries))

			sort.Slice(matchedEntries, func(i, j int) bool {
				if matchedEntries[i].RefID == matchedEntries[j].RefID {
					return matchedEntries[i].Attribute < matchedEntries[j].Attribute
				}
				return matchedEntries[i].RefID < matchedEntries[j].RefID
			})

			for idx := range test.expectedMatchedEntries {
				suite.Require().Equal(test.expectedMatchedEntries[idx].UserID, matchedEntries[idx].UserID)
				suite.Require().Equal(test.expectedMatchedEntries[idx].RefID, matchedEntries[idx].RefID)
				suite.Require().Equal(test.expectedMatchedEntries[idx].Reason, matchedEntries[idx].Reason)
				suite.Require().Equal(test.expectedMatchedEntries[idx].Attribute, matchedEntries[idx].Attribute)
				suite.Require().Equal(test.expectedMatchedEntries[idx].Value, matchedEntries[idx].Value)
				suite.Require().Equal(test.expectedMatchedEntries[idx].MatchRule, matchedEntries[idx].MatchRule)
			}
		})
	}
}

func (suite *storageSuite) TestStorage_GetRoutingSettingsForUsers() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func() Storage {
		suite.T().Helper()

		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		suite.Require().NoError(err)
		return NewStorage(clockpkg.NewMock(), logs.NullTelem, db)
	}

	routingSettingsInDatabase := func(prefix string) []*MetaSetting {
		return []*MetaSetting{
			{
				UserID: t.GetRef(prefix + "user1"),
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "123"},
					},
					CustomFields: []CustomField{
						{Name: "label_id", Value: "1"},
						{Name: "repository_id", Value: "123"},
					},
				},
			},
			{
				UserID: t.GetRef(prefix + "user1"),
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "123"},
					},
					CustomFields: []CustomField{
						{Name: "repository_id", Value: "123"},
					},
				},
			},
			{
				UserID: t.GetRef(prefix + "user1"),
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "124"},
					},
					CustomFields: []CustomField{
						{Name: "repository_id", Value: "124"},
					},
				},
			},
			{
				UserID: t.GetRef(prefix + "user2"),
				Details: SettingDetails{
					Topics: []Topic{
						{Type: "repository", Value: "123"},
					},
					CustomFields: []CustomField{
						{Name: "repository_id", Value: "123"},
					},
				},
			},
		}
	}

	testCases := []struct {
		name                    string
		dbRoutingSettings       []*MetaSetting
		userIDs                 []int64
		queryByCustomFields     []CustomField
		expectedRoutingSettings []*MetaSetting
	}{
		{
			name:                    "fetches one routing setting (filtered by two custom fields)",
			userIDs:                 []int64{t.GetRef("1get-user1")},
			dbRoutingSettings:       routingSettingsInDatabase("1get-"),
			queryByCustomFields:     []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			expectedRoutingSettings: []*MetaSetting{routingSettingsInDatabase("1get-")[0]},
		},
		{
			name:                    "fetches two routing settings (filtered by one custom field)",
			userIDs:                 []int64{t.GetRef("2get-user1")},
			dbRoutingSettings:       routingSettingsInDatabase("2get-"),
			queryByCustomFields:     []CustomField{{Name: "repository_id", Value: "123"}},
			expectedRoutingSettings: routingSettingsInDatabase("2get-")[0:2],
		},
		{
			name:                    "fetches all user routing settings if no custom fields are specified",
			userIDs:                 []int64{t.GetRef("3get-user1")},
			dbRoutingSettings:       routingSettingsInDatabase("3get-"),
			expectedRoutingSettings: routingSettingsInDatabase("3get-")[0:3],
		},
		{
			name:                    "fetches all user routing settings for all users if no custom fields are specified",
			userIDs:                 []int64{t.GetRef("4get-user1"), t.GetRef("4get-user2")},
			dbRoutingSettings:       routingSettingsInDatabase("4get-"),
			expectedRoutingSettings: routingSettingsInDatabase("4get-"),
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			rsClient := setup()

			for _, r := range test.dbRoutingSettings {
				_, err := rsClient.Create(ctx, r)
				suite.Require().NoError(err)
			}

			routingSettings, pages, err := rsClient.GetSettingsForUsers(ctx, test.userIDs, test.queryByCustomFields, pagination.NewStandardFirstPage())
			suite.Require().NoError(err)
			suite.Require().Len(routingSettings, len(test.expectedRoutingSettings))
			suite.Require().Equal("", pagination.DecodeCursor(pages.NextCursor()))

			sort.Slice(routingSettings, func(i, j int) bool {
				return routingSettings[i].ID < routingSettings[j].ID
			})

			for idx := range test.expectedRoutingSettings {
				suite.Require().Equal(test.expectedRoutingSettings[idx].UserID, routingSettings[idx].UserID)
				suite.Require().Equal(len(test.expectedRoutingSettings[idx].Details.CustomFields), len(routingSettings[idx].Details.CustomFields))
			}
		})
	}
}

func getFixtures(prefix string, t *testhelper.SequentialIDs) []*MetaSetting {
	return []*MetaSetting{
		{
			UserID: t.GetRef(prefix + "user1"),
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user1"),
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user1"),
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "124"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "124"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user2"),
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
	}
}

func (suite *storageSuite) TestStorage_GetSettings() {
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func() Storage {
		suite.T().Helper()

		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(context.Background(), db, tables)
		suite.Require().NoError(err)
		return NewStorage(clockpkg.NewMock(), logs.NullTelem, db)
	}

	testCases := []struct {
		name         string
		fixtures     []*MetaSetting
		customFields []CustomField
		expected     []*MetaSetting
	}{
		{
			name:         "fetches two routing setting (filtered by two custom fields)",
			fixtures:     getFixtures("1get-", t),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			expected:     []*MetaSetting{getFixtures("1get-", t)[0], getFixtures("1get-", t)[3]},
		},
		{
			name:         "fetches three routing settings (filtered by one custom field)",
			fixtures:     getFixtures("2get-", t),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}},
			expected:     append(getFixtures("2get-", t)[0:2], getFixtures("2get-", t)[3]),
		},
		{
			name:     "fetches all routing settings if no custom fields are specified",
			fixtures: getFixtures("3get-", t),
			expected: getFixtures("3get-", t),
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			rsClient := setup()

			for _, r := range test.fixtures {
				_, err := rsClient.Create(context.Background(), r)
				suite.Require().NoError(err)
			}

			routingSettings, pages, err := rsClient.GetSettings(context.Background(), test.customFields, pagination.NewStandardFirstPage())
			suite.Require().NoError(err)
			suite.Require().Len(routingSettings, len(test.expected))
			suite.Require().Equal("", pagination.DecodeCursor(pages.NextCursor()))

			sort.Slice(routingSettings, func(i, j int) bool {
				return routingSettings[i].ID < routingSettings[j].ID
			})

			for idx := range test.expected {
				suite.Require().Equal(test.expected[idx].UserID, routingSettings[idx].UserID)
				suite.Require().Equal(len(test.expected[idx].Details.CustomFields), len(routingSettings[idx].Details.CustomFields))
			}
		})
	}
}

func (suite *storageSuite) TestStorage_GetSettingsForUsers() {
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func() Storage {
		suite.T().Helper()

		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		err := testhelper.TruncateTables(context.Background(), db, tables)
		suite.Require().NoError(err)
		return NewStorage(clockpkg.NewMock(), logs.NullTelem, db)
	}

	testCases := []struct {
		name         string
		fixtures     []*MetaSetting
		userIDs      []int64
		customFields []CustomField
		expected     []*MetaSetting
	}{
		{
			name:         "fetches one routing setting (filtered by two custom fields)",
			userIDs:      []int64{t.GetRef("1get-user1")},
			fixtures:     getFixtures("1get-", t),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			expected:     []*MetaSetting{getFixtures("1get-", t)[0]},
		},
		{
			name:         "fetches two routing settings (filtered by one custom field)",
			userIDs:      []int64{t.GetRef("2get-user1")},
			fixtures:     getFixtures("2get-", t),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}},
			expected:     getFixtures("2get-", t)[0:2],
		},
		{
			name:     "fetches all user routing settings if no custom fields are specified",
			userIDs:  []int64{t.GetRef("3get-user1")},
			fixtures: getFixtures("3get-", t),
			expected: getFixtures("3get-", t)[0:3],
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			rsClient := setup()

			for _, r := range test.fixtures {
				_, err := rsClient.Create(context.Background(), r)
				suite.Require().NoError(err)
			}

			routingSettings, pages, err := rsClient.GetSettingsForUsers(context.Background(), test.userIDs, test.customFields, pagination.NewStandardFirstPage())
			suite.Require().NoError(err)
			suite.Require().Len(routingSettings, len(test.expected))
			suite.Require().Equal("", pagination.DecodeCursor(pages.NextCursor()))

			sort.Slice(routingSettings, func(i, j int) bool {
				return routingSettings[i].ID < routingSettings[j].ID
			})

			for idx := range test.expected {
				suite.Require().Equal(test.expected[idx].UserID, routingSettings[idx].UserID)
				suite.Require().Equal(len(test.expected[idx].Details.CustomFields), len(routingSettings[idx].Details.CustomFields))
			}
		})
	}
}

func (suite *storageSuite) TestStorage_GetSettingsForUsers_Pagination() {
	setup := func() Storage {
		suite.T().Helper()

		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_match_rules",
			"routing_setting_channels",
			"routing_setting_custom_fields",
		}
		db := suite.DB()
		err := testhelper.TruncateTables(context.Background(), db, tables)
		suite.Require().NoError(err)
		return NewStorage(clockpkg.NewMock(), logs.NullTelem, suite.DB())
	}

	seqIDs := suite.SequentialIDs()
	var fixtures []*MetaSetting
	for i := 1; i <= 10; i++ {
		fixtures = append(fixtures, &MetaSetting{
			ID:     int64(i),
			UserID: seqIDs.GetRef("user1"),
			Details: SettingDetails{
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		})
	}

	tcs := []struct {
		name             string
		expectedSettings []*MetaSetting
		page             pagination.Page
		expectedPages    pagination.Pages
	}{
		{
			name:             "no pagination: fetches all routing settings, no next cursor",
			expectedSettings: fixtures,
			page:             pagination.NewNoLimitPage(),
			expectedPages:    pagination.NewEmptyStandardPages(),
		},
		{
			name:             "pagination with higher limit than results: fetches all routing settings, no next cursor",
			expectedSettings: fixtures,
			page:             pagination.NewStandardPage("", 20),
			expectedPages:    pagination.NewEmptyStandardPages(),
		},
		{
			name:             "pagination with equal limit than results: fetches all routing settings, next cursor",
			expectedSettings: fixtures,
			page:             pagination.NewStandardPage("", 10),
			expectedPages:    pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"10"}`))),
		},
		{
			name:             "pagination with smaller limit than results: fetches first routing settings, next cursor",
			expectedSettings: fixtures[:5],
			page:             pagination.NewStandardPage("", 5),
			expectedPages:    pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`))),
		},
		{
			name:             "pagination with smaller limit than results and a cursor: fetches intermediate routing settings, next cursor",
			expectedSettings: fixtures[5:9],
			page:             pagination.NewStandardPage(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`)), 4),
			expectedPages:    pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"9"}`))),
		},
	}

	for _, tc := range tcs {
		suite.Run(tc.name, func() {
			storage := setup()
			for _, r := range fixtures {
				_, err := storage.Create(context.Background(), r)
				suite.Require().NoError(err)
			}

			settings, pages, err := storage.GetSettingsForUsers(
				context.Background(),
				[]int64{seqIDs.GetRef("user1")},
				[]CustomField{{Name: "repository_id", Value: "123"}},
				tc.page,
			)
			suite.Require().NoError(err)
			suite.Require().Len(settings, len(tc.expectedSettings))
			suite.Require().Equal(tc.expectedPages.NextCursor(), pages.NextCursor())

			sort.Slice(settings, func(i, j int) bool {
				return settings[i].ID < settings[j].ID
			})

			for i, setting := range settings {
				id := 0
				if tc.page.Cursor() != "" {
					id, _ = strconv.Atoi(pagination.DecodeCursor(tc.page.Cursor()))
				}
				suite.Require().Equal(int64(id+i+1), setting.ID)
			}
		})
	}
}

func (suite *storageSuite) assertEmptyCustomFields(metaID int64) {
	suite.T().Helper()

	sql, args, err := squirrel.Select("*").From("routing_setting_custom_fields").Where(squirrel.Eq{"meta_id": metaID}).ToSql()
	suite.Require().NoError(err)

	var fields []sqlCustomField
	err = suite.DB().Read.Select(&fields, sql, args...)
	suite.Require().NoError(err)
	suite.Require().Empty(fields)
}
