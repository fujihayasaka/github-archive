package deleterepositoryforusers

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

// Test_Subscriptions tests the handler
// by creating two subscriptions for the same user and same repository
// however one of the subscriptions has the watcher_scenario custom field.
// We check if both subscriptions have been made, after running our special handler
// we only expect to have one subscription left, the one that doesn't have the watcher_scenario.
func (s *HandlerSuite) Test_Subscriptions() {
	// create fixtures
	ctx := context.Background()
	userID := int64(1)
	repoID := int64(123)
	repoIDString := strconv.FormatInt(repoID, 10)
	repoCustomField := subscriptions.CustomField{Name: "repository_id", Value: repoIDString}
	subs := []*subscriptions.MetaSubscription{
		{
			UserID: userID,
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
					repoCustomField,
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID,
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
							subscriptions.RuleEQ("thread_type", "issue"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					repoCustomField,
				},
			},
		},
	}

	_, err := s.handler.subscriptions.BatchReplace(ctx, userID, subs, nil)
	if err != nil {
		s.Require().Fail("failed to create subscriptions", err)
	}

	// validate we have 2 subscriptions
	subsToCheck, _, err := s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, []subscriptions.CustomField{repoCustomField}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 2)

	if err := s.handler.Run(ctx, repoID, []int64{userID}); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 1 subscription left
	subsToCheck, _, err = s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, []subscriptions.CustomField{repoCustomField}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 1)
	// it should be the one that doesn't have the watcher_scenario custom field
	s.Require().Len(subsToCheck[0].Details.CustomFields, 1)
}

// Test_Settings tests the handler
// by creating two settings for the same user and same repository
// however one of the settings has the watcher_scenario custom field.
// We check if both settings have been made, after running our special handler
// we only expect to have one setting left, the one that doesn't have the watcher_scenario.
func (s *HandlerSuite) Test_Settings() {
	// create fixtures
	ctx := context.Background()
	userID := int64(1)
	repoID := int64(123)
	repoIDString := strconv.FormatInt(repoID, 10)
	repoCustomField := routing.CustomField{Name: "repository_id", Value: repoIDString}
	sets := []*routing.MetaSetting{
		{
			UserID: userID,
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
					repoCustomField,
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
					repoCustomField,
				},
			},
		},
	}

	_, err := s.handler.settings.BatchCreateAndDelete(ctx, sets, nil)
	if err != nil {
		s.Require().Fail("failed to create settings", err)
	}

	// validate we have 2 settings
	setsToCheck, _, err := s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, []routing.CustomField{repoCustomField}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 2)

	if err := s.handler.Run(ctx, repoID, []int64{userID}); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 1 setting left
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, []routing.CustomField{repoCustomField}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	// it should be the one that doesn't have the watcher_scenario custom field
	s.Require().Len(setsToCheck[0].Details.CustomFields, 1)
}

// Test_MultipleUsers tests the handler
// by creating subscriptions and settings for two different users and the same repository
// User 1 has a matching subscription. User 2 has a matching setting.
func (s *HandlerSuite) Test_MultipleUsers() {
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
							subscriptions.RuleEQ("thread_type", "issue"),
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
				CustomFields: []routing.CustomField{
					repoCustomFieldSets,
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
				CustomFields: []routing.CustomField{
					repoCustomFieldSets,
					{Name: "watcher_scenario", Value: "true"},
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
	subsToCheck, _, err := s.handler.subscriptions.GetSubscriptions(ctx, []subscriptions.CustomField{repoCustomFieldSubs}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 2)

	// validate we have 2 settings
	setsToCheck, _, err := s.handler.settings.GetSettingsForUsers(ctx, []int64{userID1, userID2}, []routing.CustomField{repoCustomFieldSets}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 2)

	// run the handler
	if err := s.handler.Run(ctx, repoID, []int64{userID1, userID2}); err != nil {
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
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID1, userID2}, []routing.CustomField{repoCustomFieldSets}, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	s.Require().Equal(userID1, setsToCheck[0].UserID)
}
