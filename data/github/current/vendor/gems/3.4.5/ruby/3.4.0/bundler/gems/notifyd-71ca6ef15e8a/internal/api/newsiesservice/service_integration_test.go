package newsiesservice

import (
	"context"
	"fmt"
	"testing"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"

	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

type NewsiesServiceSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

type expected struct {
	subscriptions []*subscriptions.MetaSubscription
	settings      []*routing.MetaSetting
}

type seeds struct {
	subscriptions []*subscriptions.MetaSubscription
	settings      []*routing.MetaSetting
}

func (s *NewsiesServiceSuite) setup(ctx context.Context) *Service {
	s.truncateTables(ctx)
	db := s.DB()
	statter := stats.NullStatter
	telem := logs.NullTelem
	clock := clockpkg.NewMock()

	settingsStorage := routing.NewStorage(clock, telem, db)
	settingsService := routing.NewSettingsService(settingsStorage, telem, statter)

	subscriptionsStorage := subscriptions.NewStorage(clock, telem, db)
	subscriptionsService := subscriptions.NewService(subscriptionsStorage, telem, statter)

	return NewService(settingsService, subscriptionsService, statter, clock)
}

func (s *NewsiesServiceSuite) Test_Integration_Watch() {
	req := s.Require()
	ctx := context.Background()
	seqIDs := s.SequentialIDs()

	expectedWatchSubscription := func(idx int) *subscriptions.MetaSubscription {
		return &subscriptions.MetaSubscription{
			Name:   "Watcher subscription",
			UserID: seqIDs.GetRef(fmt.Sprintf("user%d", idx)),
			Details: subscriptions.Details{
				Reason: ListReason,
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: seqIDs.GetRefString(fmt.Sprintf("repo%d", idx))},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules:  []subscriptions.MatchRule{subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue)},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: CategoryName, Value: "all"},
					{Name: WatcherScenarioName, Value: watcherScenarioValue},
					{Name: RepositoryIDName, Value: seqIDs.GetRefString(fmt.Sprintf("repo%d", idx))},
					{Name: OwnerIDName, Value: "1"},
					{Name: OwnerTypeName, Value: "user"},
				},
			},
		}
	}

	type watchParams struct {
		userID       int64
		refID        int64
		refType      string
		customFields []subscriptions.CustomField
	}

	tests := []struct {
		name     string
		params   watchParams
		seeds    seeds
		expected expected
	}{
		{
			name: "Watch repository on empty DB",
			params: watchParams{
				userID:  seqIDs.GetRef("user1"),
				refID:   seqIDs.GetRef("repo1"),
				refType: "Repository",
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{expectedWatchSubscription(1)},
				settings:      []*routing.MetaSetting{},
			},
		},
		{
			name: "Watch repository removes ignoring routing setting",
			params: watchParams{
				userID:  seqIDs.GetRef("user2"),
				refID:   seqIDs.GetRef("repo2"),
				refType: "Repository",
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing ignoring routing setting",
						UserID: seqIDs.GetRef("user2"),
						Details: routing.SettingDetails{
							Channels: map[string]*matchengine_dto.Channel{
								"ALL": {Enabled: false, Channel: "ALL"},
							},
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo2")},
							},
							CustomFields: []routing.CustomField{
								{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo2")},
								{Name: CategoryName, Value: "all"},
								{Name: WatcherScenarioName, Value: watcherScenarioValue},
							},
						},
					},
				},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{expectedWatchSubscription(2)},
				settings:      []*routing.MetaSetting{},
			},
		},
		{
			name: "Watch repository removes thread type subscriptions",
			params: watchParams{
				userID:  seqIDs.GetRef("user3"),
				refID:   seqIDs.GetRef("repo3"),
				refType: "Repository",
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing thread type subscription",
						UserID: seqIDs.GetRef("user1"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo3")},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo3")},
								{Name: CategoryName, Value: "thread_type"},
								{Name: WatcherScenarioName, Value: watcherScenarioValue},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{
					expectedWatchSubscription(3),
				},
				settings: []*routing.MetaSetting{},
			},
		},
		{
			name: "Watch repository doesn't affect subscriptions not related to watcher scenario",
			params: watchParams{
				userID:  seqIDs.GetRef("user4"),
				refID:   seqIDs.GetRef("repo4"),
				refType: "Repository",
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user4"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user4"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
					expectedWatchSubscription(4),
				},
				settings: []*routing.MetaSetting{},
			},
		},
		{
			name: "Watch repository doesn't affect routing settings not related to watcher scenario",
			params: watchParams{
				userID:  seqIDs.GetRef("user5"),
				refID:   seqIDs.GetRef("repo5"),
				refType: "Repository",
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing unrelated ci activity routing setting",
						UserID: seqIDs.GetRef("user5"),
						Details: routing.SettingDetails{
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo5")},
							},
							CustomFields: []routing.CustomField{
								{Name: "activity", Value: "ci_activity"},
							},
						},
					},
				},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{
					expectedWatchSubscription(5),
				},
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing unrelated ci activity routing setting",
						UserID: seqIDs.GetRef("user5"),
						Details: routing.SettingDetails{
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo5")},
							},
							CustomFields: []routing.CustomField{
								{Name: "activity", Value: "ci_activity"},
							},
						},
					},
				},
			},
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			newsiesService := s.setup(ctx)
			routingSettingsSvc := newsiesService.routingSvc
			subscriptionsSvc := newsiesService.subscriptionsSvc

			_, err := subscriptionsSvc.BatchReplace(ctx, test.params.userID, test.seeds.subscriptions, nil)
			req.NoError(err)

			_, err = routingSettingsSvc.BatchCreateAndDelete(ctx, test.seeds.settings, []int64{})
			req.NoError(err)

			err = newsiesService.Watch(ctx,
				test.params.userID,
				test.params.refID,
				test.params.refType,
				[]ThreadType{},
				test.params.customFields)
			req.NoError(err)

			actualSubscriptions, _, err := subscriptionsSvc.GetSubscriptionsForUser(ctx, test.params.userID, []subscriptions.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualSubscriptions, len(test.expected.subscriptions))

			actualRoutingSettings, _, err := routingSettingsSvc.GetSettingsForUsers(ctx, []int64{test.params.userID}, []routing.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualRoutingSettings, len(test.expected.settings))

			for i, actualSubscription := range actualSubscriptions {
				req.Equal(actualSubscription.UserID, test.expected.subscriptions[i].UserID)
				req.Equal(actualSubscription.Details.Topics, test.expected.subscriptions[i].Details.Topics)
				req.Equal(actualSubscription.Details.CustomFields, test.expected.subscriptions[i].Details.CustomFields)
				req.Equal(actualSubscription.Details.Reason, test.expected.subscriptions[i].Details.Reason)

				for j, actualFilter := range actualSubscription.Details.Filters {
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}
			}

			for i, actualRoutingSetting := range actualRoutingSettings {
				req.Equal(actualRoutingSetting.UserID, test.expected.settings[i].UserID)
				req.Equal(actualRoutingSetting.Details.Topics, test.expected.settings[i].Details.Topics)
				req.Equal(actualRoutingSetting.Details.CustomFields, test.expected.settings[i].Details.CustomFields)

				for j, actualFilter := range actualRoutingSetting.Details.Filters {
					req.Equal(test.expected.settings[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expected.settings[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expected.settings[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}

				for k, actualChannel := range actualRoutingSetting.Details.Channels {
					req.Equal(test.expected.settings[i].Details.Channels[k].Channel, actualChannel.Channel)
					req.Equal(test.expected.settings[i].Details.Channels[k].Enabled, actualChannel.Enabled)
				}
			}
		})
	}
}

func (s *NewsiesServiceSuite) Test_Integration_ThreadTypeWatch() {
	req := s.Require()
	ctx := context.Background()
	seqIDs := s.SequentialIDs()

	expectedThreadTypeWatchSubscription := func(idx int) *subscriptions.MetaSubscription {
		return &subscriptions.MetaSubscription{
			Name:   "Watch Thread type subscription",
			UserID: seqIDs.GetRef(fmt.Sprintf("user%d", idx)),
			Details: subscriptions.Details{
				Reason: ThreadTypeReason,
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: seqIDs.GetRefString(fmt.Sprintf("repo%d", idx))},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							{Attribute: WatchActivityMatchRuleName, Value: WatchActivityMatchRuleValue, MatchRule: "eq"},
							{Attribute: ThreadTypeMatchRuleName, Value: "issue", MatchRule: "eq"},
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: CategoryName, Value: "thread_type"},
					{Name: WatcherScenarioName, Value: watcherScenarioValue},
					{Name: RepositoryIDName, Value: seqIDs.GetRefString(fmt.Sprintf("repo%d", idx))},
					{Name: OwnerIDName, Value: "1"},
					{Name: OwnerTypeName, Value: "user"},
					{Name: ThreadTypeName, Value: "issue"},
				},
			},
		}
	}

	type watchParams struct {
		userID       int64
		refID        int64
		refType      string
		threadTypes  []ThreadType
		customFields []subscriptions.CustomField
	}

	tests := []struct {
		name                    string
		params                  watchParams
		dbSubscriptions         []*subscriptions.MetaSubscription
		dbRoutingSettings       []*routing.MetaSetting
		expectedSubscriptions   []*subscriptions.MetaSubscription
		expectedRoutingSettings []*routing.MetaSetting
	}{
		{
			name: "Watch repository on empty DB for Issues",
			params: watchParams{
				userID:      seqIDs.GetRef("user1"),
				refID:       seqIDs.GetRef("repo1"),
				refType:     "Repository",
				threadTypes: []ThreadType{Issue},
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			dbSubscriptions:   []*subscriptions.MetaSubscription{},
			dbRoutingSettings: []*routing.MetaSetting{},
			expectedSubscriptions: []*subscriptions.MetaSubscription{
				expectedThreadTypeWatchSubscription(1),
			},
			expectedRoutingSettings: []*routing.MetaSetting{},
		},
		{
			name: "Watch thread type on repository removes ignoring routing setting",
			params: watchParams{
				userID:      seqIDs.GetRef("user2"),
				refID:       seqIDs.GetRef("repo2"),
				refType:     "Repository",
				threadTypes: []ThreadType{Issue},
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			dbSubscriptions: []*subscriptions.MetaSubscription{},
			dbRoutingSettings: []*routing.MetaSetting{
				{
					Name:   "Existing ignoring routing setting",
					UserID: seqIDs.GetRef("user2"),
					Details: routing.SettingDetails{
						Channels: map[string]*matchengine_dto.Channel{
							"ALL": {Enabled: false, Channel: "ALL"},
						},
						Topics: []routing.Topic{
							{Type: "repository", Value: seqIDs.GetRefString("repo2")},
						},
						CustomFields: []routing.CustomField{
							{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo2")},
							{Name: CategoryName, Value: "all"},
							{Name: WatcherScenarioName, Value: watcherScenarioValue},
						},
					},
				},
			},
			expectedSubscriptions: []*subscriptions.MetaSubscription{
				expectedThreadTypeWatchSubscription(2),
			},
			expectedRoutingSettings: []*routing.MetaSetting{},
		},
		{
			name: "Watch thread type on repository removes list subscription",
			params: watchParams{
				userID:      seqIDs.GetRef("user3"),
				refID:       seqIDs.GetRef("repo3"),
				refType:     "Repository",
				threadTypes: []ThreadType{Issue},
				customFields: []subscriptions.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			dbSubscriptions: []*subscriptions.MetaSubscription{
				{
					Name:   "Existing list subscription",
					UserID: seqIDs.GetRef("user1"),
					Details: subscriptions.Details{
						Topics: []subscriptions.Topic{
							{Type: "repository", Value: seqIDs.GetRefString("repo3")},
						},
						CustomFields: []subscriptions.CustomField{
							{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo3")},
							{Name: CategoryName, Value: "all"},
							{Name: WatcherScenarioName, Value: watcherScenarioValue},
						},
					},
				},
			},
			dbRoutingSettings: []*routing.MetaSetting{},
			expectedSubscriptions: []*subscriptions.MetaSubscription{
				expectedThreadTypeWatchSubscription(3),
			},
			expectedRoutingSettings: []*routing.MetaSetting{},
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			newsiesService := s.setup(ctx)

			routingSettingsSvc := newsiesService.routingSvc
			subscriptionsSvc := newsiesService.subscriptionsSvc

			_, err := subscriptionsSvc.BatchReplace(ctx, test.params.userID, test.dbSubscriptions, nil)
			req.NoError(err)

			_, err = routingSettingsSvc.BatchCreateAndDelete(ctx, test.dbRoutingSettings, []int64{})
			req.NoError(err)

			err = newsiesService.Watch(ctx,
				test.params.userID,
				test.params.refID,
				test.params.refType,
				test.params.threadTypes,
				test.params.customFields)
			req.NoError(err)

			actualSubscriptions, _, err := subscriptionsSvc.GetSubscriptionsForUser(ctx, (test.params.userID), []subscriptions.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualSubscriptions, len(test.expectedSubscriptions))

			actualRoutingSettings, _, err := routingSettingsSvc.GetSettingsForUsers(ctx, []int64{(test.params.userID)}, []routing.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualRoutingSettings, len(test.expectedRoutingSettings))

			for i, actualSubscription := range actualSubscriptions {
				req.Equal(actualSubscription.UserID, test.expectedSubscriptions[i].UserID)
				req.Equal(actualSubscription.Details.Topics, test.expectedSubscriptions[i].Details.Topics)
				req.Equal(actualSubscription.Details.CustomFields, test.expectedSubscriptions[i].Details.CustomFields)
				req.Equal(actualSubscription.Details.Reason, test.expectedSubscriptions[i].Details.Reason)

				for j, actualFilter := range actualSubscription.Details.Filters {
					req.Equal(test.expectedSubscriptions[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expectedSubscriptions[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expectedSubscriptions[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}
			}

			for i, actualRoutingSetting := range actualRoutingSettings {
				req.Equal(actualRoutingSetting.UserID, test.expectedRoutingSettings[i].UserID)
				req.Equal(actualRoutingSetting.Details.Topics, test.expectedRoutingSettings[i].Details.Topics)
				req.Equal(actualRoutingSetting.Details.CustomFields, test.expectedRoutingSettings[i].Details.CustomFields)

				for j, actualFilter := range actualRoutingSetting.Details.Filters {
					req.Equal(test.expectedRoutingSettings[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expectedRoutingSettings[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expectedRoutingSettings[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}

				for k, actualChannel := range actualRoutingSetting.Details.Channels {
					req.Equal(test.expectedRoutingSettings[i].Details.Channels[k].Channel, actualChannel.Channel)
					req.Equal(test.expectedRoutingSettings[i].Details.Channels[k].Enabled, actualChannel.Enabled)
				}
			}
		})
	}
}

func (s *NewsiesServiceSuite) Test_Integration_Ignore() {
	req := s.Require()
	ctx := context.Background()
	seqIDs := s.SequentialIDs()

	expectedIgnoreSetting := &routing.MetaSetting{
		Name:   "Ignore routing setting",
		UserID: seqIDs.GetRef("user1"),
		Details: routing.SettingDetails{
			Topics: []routing.Topic{
				{Type: "repository", Value: seqIDs.GetRefString("repo1")},
			},
			Channels: map[string]*matchengine_dto.Channel{"ALL": {Channel: "ALL", Enabled: false}},
			Filters: []routing.SettingFilter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []routing.SettingMatchRule{
						routing.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
					},
				},
			},
			CustomFields: []routing.CustomField{
				{Name: OwnerIDName, Value: "1"},
				{Name: OwnerTypeName, Value: "user"},
				{Name: CategoryName, Value: "all"},
				{Name: WatcherScenarioName, Value: watcherScenarioValue},
				{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo1")},
			},
		},
	}

	type ignoreParams struct {
		userID       int64
		refID        int64
		refType      string
		customFields []routing.CustomField
	}

	tests := []struct {
		name     string
		params   ignoreParams
		seeds    seeds
		expected expected
	}{
		{
			name: "Ignore repository on empty DB",
			params: ignoreParams{
				userID:  seqIDs.GetRef("user1"),
				refID:   seqIDs.GetRef("repo1"),
				refType: "Repository",
				customFields: []routing.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{expectedIgnoreSetting},
			},
		},
		{
			name: "Ignore repository removes ignoring watch subscription",
			params: ignoreParams{
				userID:  seqIDs.GetRef("user1"),
				refID:   seqIDs.GetRef("repo1"),
				refType: "Repository",
				customFields: []routing.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Watcher subscription",
						UserID: seqIDs.GetRef("user1"),
						Details: subscriptions.Details{
							Reason: ListReason,
							Topics: []subscriptions.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo1")},
							},
							Filters: []subscriptions.Filter{
								{
									SubjectType: "any",
									Trigger:     "any",
									MatchRules:  []subscriptions.MatchRule{subscriptions.RuleEQ(CategoryName, categoryAllValue)},
								},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo1")},
								{Name: CategoryName, Value: "all"},
								{Name: WatcherScenarioName, Value: watcherScenarioValue},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{expectedIgnoreSetting},
			},
		},
		{
			name: "Ignore repository doesn't affect subscriptions not related to watcher scenario",
			params: ignoreParams{
				userID:  seqIDs.GetRef("user1"),
				refID:   seqIDs.GetRef("repo1"),
				refType: "Repository",
				customFields: []routing.CustomField{
					{Name: "owner_id", Value: "1"},
					{Name: "owner_type", Value: "user"},
				},
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user1"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user1"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{expectedIgnoreSetting},
			},
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			newsiesService := s.setup(ctx)
			routingSettingsSvc := newsiesService.routingSvc
			subscriptionsSvc := newsiesService.subscriptionsSvc

			_, err := subscriptionsSvc.BatchReplace(ctx, test.params.userID, test.seeds.subscriptions, nil)
			req.NoError(err)

			_, err = routingSettingsSvc.BatchCreateAndDelete(ctx, test.seeds.settings, []int64{})
			req.NoError(err)

			err = newsiesService.Ignore(ctx,
				test.params.userID,
				test.params.refID,
				test.params.refType,
				test.params.customFields)
			req.NoError(err)

			actualSubscriptions, _, err := subscriptionsSvc.GetSubscriptionsForUser(ctx, (test.params.userID), []subscriptions.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualSubscriptions, len(test.expected.subscriptions))

			actualRoutingSettings, _, err := routingSettingsSvc.GetSettingsForUsers(ctx, []int64{(test.params.userID)}, []routing.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(actualRoutingSettings, len(test.expected.settings))

			for i, actualSubscription := range actualSubscriptions {
				req.Equal(actualSubscription.UserID, test.expected.subscriptions[i].UserID)
				req.Equal(actualSubscription.Details.Topics, test.expected.subscriptions[i].Details.Topics)
				req.Equal(actualSubscription.Details.CustomFields, test.expected.subscriptions[i].Details.CustomFields)
				req.Equal(actualSubscription.Details.Reason, test.expected.subscriptions[i].Details.Reason)

				for j, actualFilter := range actualSubscription.Details.Filters {
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}
			}

			for i, actualRoutingSetting := range actualRoutingSettings {
				req.Equal(actualRoutingSetting.UserID, test.expected.settings[i].UserID)
				req.Equal(actualRoutingSetting.Details.Topics, test.expected.settings[i].Details.Topics)
				req.Equal(actualRoutingSetting.Details.CustomFields, test.expected.settings[i].Details.CustomFields)

				for j, actualFilter := range actualRoutingSetting.Details.Filters {
					req.Equal(test.expected.settings[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expected.settings[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expected.settings[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}

				for k, actualChannel := range actualRoutingSetting.Details.Channels {
					req.Equal(test.expected.settings[i].Details.Channels[k].Channel, actualChannel.Channel)
					req.Equal(test.expected.settings[i].Details.Channels[k].Enabled, actualChannel.Enabled)
				}
			}
		})
	}
}

func (s *NewsiesServiceSuite) Test_Integration_Unwatch() {
	req := s.Require()
	ctx := context.Background()
	seqIDs := s.SequentialIDs()

	type unwatchParams struct {
		userID  int64
		refID   int64
		refType string
	}
	tests := []struct {
		name     string
		params   unwatchParams
		seeds    seeds
		expected expected
	}{
		{
			name: "Unwatch repository on empty DB does nothing",
			params: unwatchParams{
				userID:  seqIDs.GetRef("user1"),
				refID:   seqIDs.GetRef("repo1"),
				refType: "Repository",
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
		},
		{
			name: "Unwatch repository removes ignoring routing setting",
			params: unwatchParams{
				userID:  seqIDs.GetRef("user2"),
				refID:   seqIDs.GetRef("repo2"),
				refType: "Repository",
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing ignoring routing setting",
						UserID: seqIDs.GetRef("user1"),
						Details: routing.SettingDetails{
							Channels: map[string]*matchengine_dto.Channel{
								"ALL": {Enabled: false, Channel: "ALL"},
							},
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo2")},
							},
							CustomFields: []routing.CustomField{
								{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo2")},
								{Name: CategoryName, Value: "all"},
								{Name: WatcherScenarioName, Value: watcherScenarioValue},
							},
						},
					},
				},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
		},
		{
			name: "Unwatch repository removes thread type subscriptions",
			params: unwatchParams{
				userID:  seqIDs.GetRef("user3"),
				refID:   seqIDs.GetRef("repo3"),
				refType: "Repository",
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing thread type subscription",
						UserID: seqIDs.GetRef("user3"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo3")},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: RepositoryIDName, Value: seqIDs.GetRefString("repo3")},
								{Name: CategoryName, Value: "thread_type"},
								{Name: WatcherScenarioName, Value: watcherScenarioValue},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings:      []*routing.MetaSetting{},
			},
		},
		{
			name: "Unwatch repository doesn't affect subscriptions not related to watcher scenario",
			params: unwatchParams{
				userID:  seqIDs.GetRef("user4"),
				refID:   seqIDs.GetRef("repo4"),
				refType: "Repository",
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user4"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
			expected: expected{
				subscriptions: []*subscriptions.MetaSubscription{
					{
						Name:   "Existing unrelated subscription",
						UserID: seqIDs.GetRef("user4"),
						Details: subscriptions.Details{
							Topics: []subscriptions.Topic{
								{Type: "issue", Value: "123"},
							},
							CustomFields: []subscriptions.CustomField{
								{Name: "thread_type", Value: "issue"},
								{Name: "thread_id", Value: "Issue"},
							},
						},
					},
				},
				settings: []*routing.MetaSetting{},
			},
		},
		{
			name: "Unwatch repository doesn't affect routing settings not related to watcher scenario",
			params: unwatchParams{
				userID:  seqIDs.GetRef("user5"),
				refID:   seqIDs.GetRef("repo5"),
				refType: "Repository",
			},
			seeds: seeds{
				subscriptions: []*subscriptions.MetaSubscription{},
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing unrelated ci activity routing setting",
						UserID: seqIDs.GetRef("user5"),
						Details: routing.SettingDetails{
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo5")},
							},
							CustomFields: []routing.CustomField{
								{Name: "activity", Value: "ci_activity"},
							},
						},
					},
				},
			},
			expected: expected{
				subscriptions: nil,
				settings: []*routing.MetaSetting{
					{
						Name:   "Existing unrelated ci activity routing setting",
						UserID: seqIDs.GetRef("user5"),
						Details: routing.SettingDetails{
							Topics: []routing.Topic{
								{Type: "repository", Value: seqIDs.GetRefString("repo5")},
							},
							CustomFields: []routing.CustomField{
								{Name: "activity", Value: "ci_activity"},
							},
						},
					},
				},
			},
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			svc := s.setup(ctx)

			settingsSvc := svc.routingSvc
			subscriptionsSvc := svc.subscriptionsSvc

			_, err := subscriptionsSvc.BatchReplace(ctx, test.params.userID, test.seeds.subscriptions, nil)
			req.NoError(err)

			_, err = settingsSvc.BatchCreateAndDelete(ctx, test.seeds.settings, []int64{})
			req.NoError(err)

			err = svc.Unwatch(ctx, test.params.userID, []int64{test.params.refID}, test.params.refType)
			req.NoError(err)

			gotSubscriptions, _, err := subscriptionsSvc.GetSubscriptionsForUser(ctx, test.params.userID, []subscriptions.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(gotSubscriptions, len(test.expected.subscriptions))

			gotSettings, _, err := settingsSvc.GetSettingsForUsers(ctx, []int64{test.params.userID}, []routing.CustomField{}, pagination.NewStandardFirstPage())
			req.NoError(err)
			req.Len(gotSettings, len(test.expected.settings))

			for i, subscription := range gotSubscriptions {
				req.Equal(subscription.UserID, test.expected.subscriptions[i].UserID)
				req.Equal(subscription.Details.Topics, test.expected.subscriptions[i].Details.Topics)
				req.Equal(subscription.Details.CustomFields, test.expected.subscriptions[i].Details.CustomFields)
				req.Equal(subscription.Details.Reason, test.expected.subscriptions[i].Details.Reason)

				for j, actualFilter := range subscription.Details.Filters {
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].SubjectType, actualFilter.SubjectType)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].Trigger, actualFilter.Trigger)
					req.Equal(test.expected.subscriptions[i].Details.Filters[j].MatchRules, actualFilter.MatchRules)
				}
			}

			for i, setting := range gotSettings {
				req.Equal(setting.UserID, test.expected.settings[i].UserID)
				req.Equal(setting.Details.Topics, test.expected.settings[i].Details.Topics)
				req.Equal(setting.Details.CustomFields, test.expected.settings[i].Details.CustomFields)

				for j, filter := range setting.Details.Filters {
					req.Equal(test.expected.settings[i].Details.Filters[j].SubjectType, filter.SubjectType)
					req.Equal(test.expected.settings[i].Details.Filters[j].Trigger, filter.Trigger)
					req.Equal(test.expected.settings[i].Details.Filters[j].MatchRules, filter.MatchRules)
				}

				for k, channel := range setting.Details.Channels {
					req.Equal(test.expected.settings[i].Details.Channels[k].Channel, channel.Channel)
					req.Equal(test.expected.settings[i].Details.Channels[k].Enabled, channel.Enabled)
				}
			}
		})
	}
}

func (s *NewsiesServiceSuite) truncateTables(ctx context.Context) {
	s.T().Helper()

	tables := []string{
		"meta_subscriptions",
		"subscriptions_v2",
		"subscription_match_rules",
		"subscription_custom_fields",
		"meta_routing_settings",
		"routing_settings",
		"routing_setting_channels",
		"routing_setting_match_rules",
		"routing_setting_custom_fields",
	}
	s.Require().NoError(testhelper.TruncateTables(ctx, s.DB(), tables))
}

func TestNewsiesServiceIntegrationTest(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	testsuite.Run(t, new(NewsiesServiceSuite))
}
