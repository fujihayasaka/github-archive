package deleteuserrepositories

import (
	"context"
	"strconv"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

type HandlerSuite struct {
	suite.Suite
	testhelper.DatabaseSuite
	handler *Handler
}

func Test_HandlerSuite(t *testing.T) {
	suite.Run(t, new(HandlerSuite))
}

func (s *HandlerSuite) SetupTest() {
	s.SetupDB() // sets up the database and also truncates all tables

	c := clock.NewMock()
	telem := logs.NullTelem

	subSvc := subscriptions.NewService(subscriptions.NewStorage(c, telem, s.DB()), telem, stats.NullStatter)
	routeSvc := routing.NewSettingsService(routing.NewStorage(c, telem, s.DB()), telem, stats.NullStatter)

	// create handler
	s.handler = NewHandler(
		clock.NewMock(),
		logs.NullTelem,
		stats.NullStatter,
		subSvc,
		routeSvc,
	)
}

// TestDeleteRepositoryHandler_Subscriptions tests the delete repository handler
// by creating three subscriptions for the same user and different repositories
// however one of the subscriptions does not have the watcher_scenario flag
func (s *HandlerSuite) TestDeleteRepositoryHandler_Subscriptions() {
	// create fixtures
	ctx := context.Background()
	userID := int64(1)

	subs := []*subscriptions.MetaSubscription{
		{
			UserID: userID,
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							subscriptions.RuleEQ("watch_activity", "true"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "123"},
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID,
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "456"},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							subscriptions.RuleEQ("watch_activity", "true"),
							subscriptions.RuleEQ("thread_type", "issue"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "456"},
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID,
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "789"},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							subscriptions.RuleEQ("watch_activity", "true"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "789"},
				},
			},
		},
	}

	_, err := s.handler.subscriptions.BatchReplace(ctx, userID, subs, nil)
	if err != nil {
		s.Require().Fail("failed to create subscriptions", err)
	}

	// validate we have 3 subscriptions
	subsToCheck, _, err := s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 3)

	if err := s.handler.Run(ctx, userID, []int64{123, 456, 789}); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 1 subscription left
	subsToCheck, _, err = s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 1)
	// it should be the one that doesn't have the watcher_scenario custom field
	s.Require().Len(subsToCheck[0].Details.CustomFields, 1)
	// or more precisely the one for repo 789
	s.Require().Equal("789", subsToCheck[0].Details.CustomFields[0].Value)
}

// TestDeleteRepositoryHandler_Settings tests the delete repository handler
// by creating two settings for the same user and different repositories
// however one of the settings has the watcher_scenario custom field.
// We check if both settings have been made, after running our special handler
// we only expect to have one setting left, the one that doesn't have the watcher_scenario.
func (s *HandlerSuite) TestDeleteRepositoryHandler_Settings() {
	// create fixtures
	ctx := context.Background()
	userID := int64(1)
	sets := []*routing.MetaSetting{
		{
			UserID: userID,
			Details: routing.SettingDetails{
				Channels: map[string]*dto.Channel{
					"EMAIL": {Channel: "EMAIL", Enabled: true},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []routing.SettingFilter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []routing.SettingMatchRule{
							{Attribute: "has_label", Value: "2", MatchRule: "list"},
							{Attribute: "body", Value: "sub", MatchRule: "contains"},
						},
					},
				},
				CustomFields: []routing.CustomField{
					{Name: "repository_id", Value: "123"},
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID,
			Details: routing.SettingDetails{
				Channels: map[string]*dto.Channel{
					"EMAIL": {Channel: "EMAIL", Enabled: true},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: "456"},
				},
				Filters: []routing.SettingFilter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []routing.SettingMatchRule{
							{Attribute: "has_label", Value: "2", MatchRule: "list"},
							{Attribute: "body", Value: "sub", MatchRule: "contains"},
						},
					},
				},
				CustomFields: []routing.CustomField{
					{Name: "repository_id", Value: "456"},
				},
			},
		},
	}

	_, err := s.handler.settings.BatchCreateAndDelete(ctx, sets, nil)
	if err != nil {
		s.Require().Fail("failed to create settings", err)
	}

	// validate we have 2 settings
	setsToCheck, _, err := s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 2)

	if err := s.handler.Run(ctx, userID, []int64{123, 456}); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 1 setting left
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	// it should be the one that doesn't have the watcher_scenario custom field
	s.Require().Len(setsToCheck[0].Details.CustomFields, 1)
	// or more precisely the one for repo 456
	s.Require().Equal("456", setsToCheck[0].Details.CustomFields[0].Value)
}

// TestDeleteRepositoryHandler_MultipleUsers tests the delete repository handler
// by creating subscriptions and settings for two different users and the same repository
// User 1 has a matching subscription. User 2 has a matching setting.
func (s *HandlerSuite) TestDeleteRepositoryHandler_MultipleUsers() {
	// create subscription fixtures
	ctx := context.Background()
	userID1 := int64(1)
	userID2 := int64(2)
	repoID := int64(123)
	repoIDString := strconv.FormatInt(repoID, 10)
	repoCustomFieldSubs := subscriptions.CustomField{Name: "repository_id", Value: repoIDString}
	repoCustomFieldSets := routing.CustomField{Name: "repository_id", Value: repoIDString}
	subs := []*subscriptions.MetaSubscription{
		{
			UserID: userID1,
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: repoIDString},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							subscriptions.RuleEQ("watch_activity", "true"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					repoCustomFieldSubs,
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID2,
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: repoIDString},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []subscriptions.MatchRule{
							subscriptions.RuleEQ("watch_activity", "true"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					repoCustomFieldSubs,
				},
			},
		},
	}
	sets := []*routing.MetaSetting{
		{
			UserID: userID1,
			Details: routing.SettingDetails{
				Channels: map[string]*dto.Channel{
					"EMAIL": {Channel: "EMAIL", Enabled: true},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: repoIDString},
				},
				Filters: []routing.SettingFilter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []routing.SettingMatchRule{
							{Attribute: "has_label", Value: "2", MatchRule: "list"},
							{Attribute: "body", Value: "sub", MatchRule: "contains"},
						},
					},
				},
				CustomFields: []routing.CustomField{
					repoCustomFieldSets,
				},
			},
		},
		{
			UserID: userID2,
			Details: routing.SettingDetails{
				Channels: map[string]*dto.Channel{
					"EMAIL": {Channel: "EMAIL", Enabled: true},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: repoIDString},
				},
				Filters: []routing.SettingFilter{
					{
						SubjectType: "any",
						Trigger:     "any",
						MatchRules: []routing.SettingMatchRule{
							{Attribute: "has_label", Value: "2", MatchRule: "list"},
							{Attribute: "body", Value: "sub", MatchRule: "contains"},
						},
					},
				},
				CustomFields: []routing.CustomField{
					repoCustomFieldSets,
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
	}

	// create subscriptions and settings
	_, err := s.handler.subscriptions.BatchReplace(ctx, userID1, []*subscriptions.MetaSubscription{subs[0]}, nil)
	if err != nil {
		s.Require().Fail("failed to create subscriptions for user 1", err)
	}
	_, err = s.handler.subscriptions.BatchReplace(ctx, userID2, []*subscriptions.MetaSubscription{subs[1]}, nil)
	if err != nil {
		s.Require().Fail("failed to create subscriptions for user 2", err)
	}
	_, err = s.handler.settings.BatchCreateAndDelete(ctx, sets, nil)
	if err != nil {
		s.Require().Fail("failed to create settings", err)
	}

	// validate we have 2 subscriptions
	subsToCheck, _, err := s.handler.subscriptions.GetSubscriptions(ctx, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 2)

	// validate we have 2 settings
	setsToCheck, _, err := s.handler.settings.GetSettingsForUsers(ctx, []int64{userID1, userID2}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 2)

	// run the handler
	extraRepoID := int64(456) // adding this should have no negative effect
	if err := s.handler.Run(ctx, userID1, []int64{repoID, extraRepoID}); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 1 subscription left and it belongs to user 2
	subsToCheck, _, err = s.handler.subscriptions.GetSubscriptions(ctx, []subscriptions.CustomField{repoCustomFieldSubs}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 1)
	s.Require().Equal(userID2, subsToCheck[0].UserID)

	// validate we have 1 setting left and it belongs to user 1
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID1}, []routing.CustomField{repoCustomFieldSets}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	s.Require().Equal(userID1, setsToCheck[0].UserID)
}
