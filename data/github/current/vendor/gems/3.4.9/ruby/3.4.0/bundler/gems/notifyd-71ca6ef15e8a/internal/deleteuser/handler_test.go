package deleteuser

import (
	"context"
	"errors"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/devicetokens"
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
	tokens  *devicetokens.StorageMock
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

	s.tokens = devicetokens.NewStorageMock(s.T())

	// create handler
	s.handler = NewHandler(
		clock.NewMock(),
		logs.NullTelem,
		stats.NullStatter,
		subSvc,
		routeSvc,
		s.tokens,
	)
}

// Test_Subscriptions tests the deletion of subscriptions
// two subscriptions are created for two different users
// we expect to only find one subscription for our user
// and after the handler is run we expect to find no subscriptions for them
func (s *HandlerSuite) Test_Subscriptions() {
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
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: int64(2),
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
							subscriptions.RuleEQ("thread_type", "issue"),
						},
					},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
	}

	created, err := s.handler.subscriptions.BatchReplace(ctx, userID, subs, nil)
	if err != nil {
		s.Require().Fail("failed to create subscriptions", err)
	}
	// make sure both subscriptions have been created
	s.Require().Len(created, 2)

	// validate we have 1 subscription for the user
	subsToCheck, _, err := s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 1)
	s.Require().Equal(subsToCheck[0].UserID, userID)

	// Mock the call to device tokens deletion
	s.tokens.On("DeleteAll", mock.Anything, userID).Return(nil).Once()

	if err := s.handler.Run(ctx, userID); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 0 subscriptions left
	subsToCheck, _, err = s.handler.subscriptions.GetSubscriptionsForUser(ctx, userID, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Empty(subsToCheck)
}

// Test_Settings tests the deletion of settings
// two settings are created for two different users
func (s *HandlerSuite) Test_Settings() {
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
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: int64(2),
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
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
	}

	_, err := s.handler.settings.BatchCreateAndDelete(ctx, sets, nil)
	if err != nil {
		s.Require().Fail("failed to create settings", err)
	}

	// validate we have 1 settings
	setsToCheck, _, err := s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	s.Require().Equal(setsToCheck[0].UserID, userID)

	// Mock the call to device tokens deletion
	s.tokens.On("DeleteAll", mock.Anything, userID).Return(nil).Once()

	if err := s.handler.Run(ctx, userID); err != nil {
		s.Require().Fail("failed to run handler", err)
	}

	// validate we have 0 settings left
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Empty(setsToCheck)
}

// Test_MultipleUsers tests the handler when multiple users are involved
// by creating subscriptions and settings for two different users
// User 1 has a matching subscription. User 2 has a matching setting.
func (s *HandlerSuite) Test_MultipleUsers() {
	// create subscription fixtures
	ctx := context.Background()
	userID1 := int64(1)
	userID2 := int64(2)

	subs := []*subscriptions.MetaSubscription{
		{
			UserID: userID1,
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
					{Name: "watcher_scenario", Value: "true"},
				},
			},
		},
		{
			UserID: userID2,
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
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"},
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

	// Mock the call to device tokens deletion
	s.tokens.On("DeleteAll", mock.Anything, userID1).Return(nil).Once()

	// run the handler for user 1
	if err := s.handler.Run(ctx, userID1); err != nil {
		s.Require().Fail("failed to run handler for user 1", err)
	}

	// Mock the call to device tokens deletion
	s.tokens.On("DeleteAll", mock.Anything, userID2).Return(nil).Once()

	// run the handler for user 2
	if err := s.handler.Run(ctx, userID2); err != nil {
		s.Require().Fail("failed to run handler for user 2", err)
	}

	// validate we have 1 subscription left and it belongs to user 2
	subsToCheck, _, err = s.handler.subscriptions.GetSubscriptions(ctx, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get subscriptions", err)
	}
	s.Require().Len(subsToCheck, 1)
	s.Require().Equal(userID2, subsToCheck[0].UserID)

	// validate we have 2 setting left and it belongs to user 1
	setsToCheck, _, err = s.handler.settings.GetSettingsForUsers(ctx, []int64{userID1, userID2}, nil, pagination.NewStandardFirstPage())
	if err != nil {
		s.Require().Fail("failed to get settings", err)
	}
	s.Require().Len(setsToCheck, 1)
	s.Require().Equal(userID1, setsToCheck[0].UserID)
}

func (s *HandlerSuite) TestDeviceTokens_OK() {
	s.tokens.On("DeleteAll", mock.Anything, int64(1)).Return(nil).Once()
	s.Require().NoError(s.handler.Run(context.Background(), 1))
}

func (s *HandlerSuite) TestDeviceTokens_StorageError() {
	s.tokens.On("DeleteAll", mock.Anything, int64(1)).Return(errors.New("")).Once()
	s.Require().Error(s.handler.Run(context.Background(), 1))
}
