package routingsettingsserver

import (
	"context"
	"fmt"
	"sort"
	"testing"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
	pb "github.com/github/notifyd/proto/services/routingsettings"
)

type RoutingSettingsServerTestIntegrationSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func TestRoutingSettingsServerTestSuite(t *testing.T) {
	testsuite.Run(t, new(RoutingSettingsServerTestIntegrationSuite))
}

func fixtures(prefix string, t *testhelper.SequentialIDs) []*routing.MetaSetting {
	return []*routing.MetaSetting{
		{
			UserID: t.GetRef(prefix + "user12"),
			Name:   "test settings 1",
			Details: routing.SettingDetails{
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []routing.CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user12"),
			Name:   "test settings 2",
			Details: routing.SettingDetails{
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []routing.CustomField{
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user12"),
			Name:   "test settings 3",
			Details: routing.SettingDetails{
				Topics: []routing.Topic{
					{Type: "repository", Value: "124"},
				},
				CustomFields: []routing.CustomField{
					{Name: "repository_id", Value: "124"},
				},
			},
		},
		{
			UserID: t.GetRef(prefix + "user24"),
			Name:   "test settings 4",
			Details: routing.SettingDetails{
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []routing.CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
	}
}

func setup(t *testing.T, db mysql.DB) (routing.Storage, *Server) {
	t.Helper()

	tables := []string{
		"meta_routing_settings",
		"routing_settings",
		"routing_setting_channels",
		"routing_setting_match_rules",
		"routing_setting_custom_fields",
	}
	if err := testhelper.TruncateTables(context.Background(), db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	clock := clockpkg.NewMock()
	storage := routing.NewStorage(clock, logs.NullTelem, db)
	service := routing.NewSettingsService(storage, logs.NullTelem, stats.NullStatter)
	server := NewServer(service, logs.NullTelem, stats.NullStatter, clock)
	return storage, server
}

func (suite *RoutingSettingsServerTestIntegrationSuite) TestGet() {
	t := suite.SequentialIDs()
	testCases := []struct {
		name     string
		fixtures []*routing.MetaSetting
		request  *pb.GetRequest
	}{
		{
			name: "fetches one routing setting (filtered by two custom fields)",
			request: &pb.GetRequest{
				UserId:               t.GetRefInt32("1get-user12"),
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			},
			fixtures: fixtures("1get-", t)[0:1],
		},
		{
			name: "fetches two routing settings (filtered by one custom field)",
			request: &pb.GetRequest{
				UserId:               t.GetRefInt32("2get-user12"),
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}},
			},
			fixtures: fixtures("2get-", t)[0:2],
		},
		{
			name: "fetches all user routing settings if no custom fields are specified",
			request: &pb.GetRequest{
				UserId: t.GetRefInt32("3get-user12"),
			},
			fixtures: fixtures("3get-", t)[0:3],
		},
		{
			name: "no user: fetches two routing setting (filtered by two custom fields)",
			request: &pb.GetRequest{
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			},
			fixtures: []*routing.MetaSetting{fixtures("1get-", t)[0], fixtures("1get-", t)[3]},
		},
		{
			name: "no user: fetches three routing settings (filtered by one custom field)",
			request: &pb.GetRequest{
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}},
			},
			fixtures: append(fixtures("2get-", t)[0:2], fixtures("2get-", t)[3]),
		},
		{
			name:     "no user: fetches all user routing settings if no custom fields are specified",
			request:  &pb.GetRequest{},
			fixtures: fixtures("3get-", t)[0:4],
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage, server := setup(suite.T(), suite.DB())

			_, err := storage.BatchCreateAndDelete(context.Background(), test.fixtures, nil)
			suite.Require().NoError(err)

			response, err := server.Get(context.Background(), test.request)
			suite.Require().NoError(err)

			routingSettings := response.RoutingSetting

			suite.Require().Len(routingSettings, len(test.fixtures))

			sort.Slice(routingSettings, func(i, j int) bool {
				return routingSettings[i].Id < routingSettings[j].Id
			})

			for idx := range test.fixtures {
				suite.Require().Equal(test.fixtures[idx].UserID, int64(routingSettings[idx].UserId))
				suite.Require().Equal(len(test.fixtures[idx].Details.CustomFields), len(routingSettings[idx].CustomFields))
			}
		})
	}
}

func (suite *RoutingSettingsServerTestIntegrationSuite) TestBatchGet() {
	t := suite.SequentialIDs()
	testCases := []struct {
		name     string
		fixtures []*routing.MetaSetting
		request  *pb.BatchGetRequest
	}{
		{
			name: "fetches one routing setting (filtered by two custom fields)",
			request: &pb.BatchGetRequest{
				UserIds:              []int32{t.GetRefInt32("1get-user12")},
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			},
			fixtures: fixtures("1get-", t)[0:1],
		},
		{
			name: "fetches two routing settings (filtered by one custom field)",
			request: &pb.BatchGetRequest{
				UserIds:              []int32{t.GetRefInt32("2get-user12")},
				FilterByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}},
			},
			fixtures: fixtures("2get-", t)[0:2],
		},
		{
			name: "fetches all user routing settings if no custom fields are specified",
			request: &pb.BatchGetRequest{
				UserIds: []int32{t.GetRefInt32("3get-user12")},
			},
			fixtures: fixtures("3get-", t)[0:3],
		},
		{
			name: "fetches all user routing settings for all users if no custom fields are specified",
			request: &pb.BatchGetRequest{
				UserIds: []int32{t.GetRefInt32("4get-user12"), t.GetRefInt32("4get-user24")},
			},
			fixtures: fixtures("4get-", t),
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage, server := setup(suite.T(), suite.DB())

			_, err := storage.BatchCreateAndDelete(context.Background(), test.fixtures, nil)
			suite.Require().NoError(err)

			response, err := server.BatchGet(context.Background(), test.request)
			suite.Require().NoError(err)

			routingSettings := response.RoutingSetting

			suite.Require().Len(routingSettings, len(test.fixtures))

			sort.Slice(routingSettings, func(i, j int) bool {
				return routingSettings[i].Id < routingSettings[j].Id
			})

			for idx := range test.fixtures {
				suite.Require().Equal(test.fixtures[idx].UserID, int64(routingSettings[idx].UserId))
				suite.Require().Equal(len(test.fixtures[idx].Details.CustomFields), len(routingSettings[idx].CustomFields))
			}
		})
	}
}

func (suite *RoutingSettingsServerTestIntegrationSuite) Test_BatchReplace_Integration_Success() {
	var userID int64 = 1
	ctx := context.Background()
	filters := []*pb.Filter{
		{
			SubjectType: "issue",
			Trigger:     "created",
			MatchRules: []*pb.MatchRule{
				{Attribute: "has_label", Value: "1", MatchRule: "list"},
				{Attribute: "title", Value: "sub", MatchRule: "contains"},
			},
		},
	}
	settingsToCreate := []*pb.Setting{
		{
			Topics:       []*pb.Topic{{Type: "repository", Value: "123"}, {Type: "repository", Value: "456"}},
			Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
			CustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			Filters:      filters,
		},
	}

	replaceByCustomFields := []*pb.CustomField{
		{Name: "field name 1", Value: "field value 1"},
		{Name: "field name 2", Value: "field value 2"},
	}

	batchReplaceRequest := pb.BatchReplaceRequest{
		UserId:                int32(userID),
		Settings:              settingsToCreate,
		ReplaceByCustomFields: replaceByCustomFields,
	}

	expectedMetaSettingsToCreate := []*routing.MetaSetting{
		{
			UserID: 1,
			Details: routing.SettingDetails{
				Topics: []routing.Topic{
					{Type: "repository", Value: "123"}, {Type: "repository", Value: "456"},
				},
				CustomFields: []routing.CustomField{
					{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"},
				},
				Channels: map[string]*matchengine_dto.Channel{
					"EMAIL": {Channel: "EMAIL", Enabled: true},
				},
				Filters: []routing.SettingFilter{
					{
						SubjectType: "issue",
						Trigger:     "created",
						MatchRules: []routing.SettingMatchRule{
							{Attribute: "has_label", Value: "1", MatchRule: "list"},
							{Attribute: "title", Value: "sub", MatchRule: "contains"},
						},
					},
				},
			},
		},
	}

	expectedFields := []routing.CustomField{
		{Name: "field name 1", Value: "field value 1"},
		{Name: "field name 2", Value: "field value 2"},
	}

	mockStorage := routing.NewStorageMock(suite.T())
	mockStorage.
		On("BatchReplace", mock.Anything, userID, expectedMetaSettingsToCreate, expectedFields).
		Return([]int64{1}, nil)

	service := routing.NewSettingsService(mockStorage, logs.NullTelem, stats.NullStatter)
	s := Server{service: service}

	response, err := s.BatchReplace(ctx, &batchReplaceRequest)
	suite.Require().NoError(err)
	suite.Require().Equal([]int64{1}, response.GetCreatedIds())
}

func (suite *RoutingSettingsServerTestIntegrationSuite) Test_BatchReplace_Integration_Failure() {
	var userID int64 = 1
	ctx := context.Background()
	filters := []*pb.Filter{
		{
			SubjectType: "issue",
			Trigger:     "created",
			MatchRules: []*pb.MatchRule{
				{Attribute: "has_label", Value: "1", MatchRule: "list"},
			},
		},
	}
	settingsToCreate := []*pb.Setting{
		{
			Topics: []*pb.Topic{
				{Type: "repository", Value: "456"},
			},
			Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
			CustomFields: []*pb.CustomField{},
			Filters:      filters,
		},
	}

	replaceByCustomFields := []*pb.CustomField{
		{Name: "field name 1", Value: "field value 1"},
	}

	batchReplaceRequest := pb.BatchReplaceRequest{
		UserId:                int32(userID),
		Settings:              settingsToCreate,
		ReplaceByCustomFields: replaceByCustomFields,
	}

	expectedFields := []routing.CustomField{
		{Name: "field name 1", Value: "field value 1"},
	}

	mockStorage := routing.NewStorageMock(suite.T())
	mockStorage.
		On("BatchReplace", mock.Anything, userID, mock.AnythingOfType("[]*routing.MetaSetting"), expectedFields).
		Return([]int64{}, errors.New("internal error")).
		Once()

	service := routing.NewSettingsService(mockStorage, logs.NullTelem, stats.NullStatter)

	s := Server{service: service}

	response, err := s.BatchReplace(ctx, &batchReplaceRequest)
	suite.Require().Nil(response)
	suite.Require().Error(err)
	suite.Require().ErrorContains(err, "Failed to batch replace settings")
	suite.Require().NotContains(err.Error(), "internal error")
}
