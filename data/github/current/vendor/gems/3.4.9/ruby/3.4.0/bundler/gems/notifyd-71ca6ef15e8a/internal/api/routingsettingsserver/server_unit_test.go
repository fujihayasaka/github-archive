package routingsettingsserver

import (
	"context"
	"testing"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	pb "github.com/github/notifyd/proto/services/routingsettings"
)

type suite struct {
	testsuite.Suite
}

func (suite *suite) TestGet_Unit_Success() {
	tcs := []struct {
		name          string
		page          *pb.Page
		expectedPage  pagination.Page
		pages         pagination.Pages
		expectedPages *pb.Pages
	}{
		{
			"no page given no cursor returned",
			nil,
			pagination.NewNoLimitPage(), // TODO: Update with first page after pagination is implemented on the monolith
			pagination.NewEmptyStandardPages(),
			nil,
		},
		{
			"no page given next cursor returned",
			nil,
			pagination.NewNoLimitPage(), // TODO: Update with first page after pagination is implemented on the monolith
			pagination.NewStandardPages(pagination.EncodeV1Cursor("1")),
			&pb.Pages{Next: pagination.EncodeV1Cursor("1")},
		},
		{
			"pages given no cursor returned",
			&pb.Page{Cursor: pagination.EncodeV1Cursor("1"), Limit: int64(2)},
			pagination.NewStandardPage(pagination.EncodeV1Cursor("1"), int64(2)),
			pagination.NewEmptyStandardPages(),
			nil,
		},
		{
			"pages given cursor returned",
			&pb.Page{Cursor: pagination.EncodeV1Cursor("1"), Limit: int64(2)},
			pagination.NewStandardPage(pagination.EncodeV1Cursor("1"), int64(2)),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("3")),
			&pb.Pages{Next: pagination.EncodeV1Cursor("3")},
		},
	}

	for _, tc := range tcs {
		suite.Run(tc.name, func() {
			service := routing.NewServiceMock(suite.T())
			s := NewServer(service, logs.NullTelem, stats.NullStatter, clockpkg.NewMock())

			request := &pb.GetRequest{
				UserId: 1,
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
				Page: tc.page,
			}

			service.
				On("GetSettingsForUsers", mock.Anything, []int64{1}, []routing.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
				Return([]*routing.MetaSetting{}, tc.pages, nil)

			result, err := s.Get(context.Background(), request)
			suite.Require().NoError(err)

			if tc.expectedPages == nil {
				suite.Require().Nil(result.GetPages())
			} else {
				suite.Require().Equal(tc.expectedPages.Next, result.GetPages().GetNext())
			}
		})
	}
}

func (suite *suite) TestGet_Unit_Failure() {
	tcs := []struct {
		name  string
		error error
		msg   string
	}{
		{
			"page limit error",
			pagination.NewLimitExceededError(1000, 1001),
			"Requested page limit 1001 exceeds upper limit 1000",
		},
		{
			"other internal error",
			errors.New("some other internal error"),
			"Failed to get routing settings",
		},
	}

	for _, tc := range tcs {
		suite.Run(tc.name, func() {
			service := routing.NewServiceMock(suite.T())
			s := NewServer(service, logs.NullTelem, stats.NullStatter, clockpkg.NewMock())

			request := &pb.GetRequest{
				UserId: 1,
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
			}

			service.
				On("GetSettingsForUsers", mock.Anything, []int64{1}, []routing.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, pagination.NewNoLimitPage()). // TODO: Update with first page after pagination is implemented on the monolith
				Return(nil, pagination.NewEmptyStandardPages(), tc.error)

			result, err := s.Get(context.Background(), request)
			suite.Require().ErrorContains(err, tc.msg)
			suite.Require().Nil(result.GetPages())
		})
	}
}

func (suite *suite) TestBatchGet_Unit_Success() {
	tcs := []struct {
		name          string
		page          *pb.Page
		expectedPage  pagination.Page
		pages         pagination.Pages
		expectedPages *pb.Pages
	}{
		{
			"no page given no cursor returned",
			nil,
			pagination.NewNoLimitPage(), // TODO: Update with first page after pagination is implemented on the monolith
			pagination.NewEmptyStandardPages(),
			nil,
		},
		{
			"no page given next cursor returned",
			nil,
			pagination.NewNoLimitPage(), // TODO: Update with first page after pagination is implemented on the monolith
			pagination.NewStandardPages(pagination.EncodeV1Cursor("1")),
			&pb.Pages{Next: pagination.EncodeV1Cursor("1")},
		},
		{
			"pages given no cursor returned",
			&pb.Page{Cursor: pagination.EncodeV1Cursor("1"), Limit: int64(2)},
			pagination.NewStandardPage(pagination.EncodeV1Cursor("1"), int64(2)),
			pagination.NewEmptyStandardPages(),
			nil,
		},
		{
			"pages given cursor returned",
			&pb.Page{Cursor: pagination.EncodeV1Cursor("1"), Limit: int64(2)},
			pagination.NewStandardPage(pagination.EncodeV1Cursor("1"), int64(2)),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("3")),
			&pb.Pages{Next: pagination.EncodeV1Cursor("3")},
		},
	}

	for _, tc := range tcs {
		suite.Run(tc.name, func() {
			service := routing.NewServiceMock(suite.T())
			s := NewServer(service, logs.NullTelem, stats.NullStatter, clockpkg.NewMock())

			request := &pb.BatchGetRequest{
				UserIds: []int32{1},
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
				Page: tc.page,
			}

			service.
				On("GetSettingsForUsers", mock.Anything, []int64{1}, []routing.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
				Return([]*routing.MetaSetting{}, tc.pages, nil)

			result, err := s.BatchGet(context.Background(), request)
			suite.Require().NoError(err)

			if tc.expectedPages == nil {
				suite.Require().Nil(result.GetPages())
			} else {
				suite.Require().Equal(tc.expectedPages.Next, result.GetPages().GetNext())
			}
		})
	}
}

func (suite *suite) TestBatchGet_Unit_Failure() {
	tcs := []struct {
		name  string
		error error
		msg   string
	}{
		{
			"page limit error",
			pagination.NewLimitExceededError(1000, 1001),
			"Requested page limit 1001 exceeds upper limit 1000",
		},
		{
			"other internal error",
			errors.New("some other internal error"),
			"Failed to get routing settings",
		},
	}

	for _, tc := range tcs {
		suite.Run(tc.name, func() {
			service := routing.NewServiceMock(suite.T())
			s := NewServer(service, logs.NullTelem, stats.NullStatter, clockpkg.NewMock())

			request := &pb.BatchGetRequest{
				UserIds: []int32{1},
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
			}

			service.
				On("GetSettingsForUsers", mock.Anything, []int64{1}, []routing.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, pagination.NewNoLimitPage()). // TODO: Update with first page after pagination is implemented on the monolith
				Return(nil, pagination.NewEmptyStandardPages(), tc.error)

			result, err := s.BatchGet(context.Background(), request)
			suite.Require().ErrorContains(err, tc.msg)
			suite.Require().Nil(result.GetPages())
		})
	}
}

func (suite *suite) TestBatchCreateAndDelete_Unit_Success() {
	clock := clockpkg.NewMock()
	ts := mysql.NewTimestamps(clock)

	routingSettingsServiceMock := new(routing.ServiceMock)

	expectedToCreate := []*routing.MetaSetting{
		{
			UserID: 1,
			Name:   "Test settings 1",
			Details: routing.SettingDetails{
				Channels: map[string]*matchengine_dto.Channel{
					"EMAIL": {
						Channel: "EMAIL",
						Enabled: true,
					},
					"PUSH": {
						Channel: "PUSH",
						Enabled: true,
					},
				},
				Filters: []routing.SettingFilter{
					{
						Reason:      "ci_activity",
						Trigger:     "created",
						SubjectType: "CheckSuite",
						MatchRules: []routing.SettingMatchRule{
							{
								Attribute: "failed",
								Value:     "true",
								MatchRule: "eq",
							},
						},
					},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: "1"},
				},
				CustomFields: []routing.CustomField{
					{
						Name:  "delivery_group",
						Value: "ci_activity",
					},
				},
			},
			Timestamps: ts,
		},
		{
			UserID: 2,
			Name:   "Test settings 2",
			Details: routing.SettingDetails{
				Channels: map[string]*matchengine_dto.Channel{
					"EMAIL": {
						Channel: "EMAIL",
						Enabled: false,
					},
					"PUSH": {
						Channel: "PUSH",
						Enabled: true,
					},
				},
				Filters: []routing.SettingFilter{
					{
						Reason:     "ci_activity",
						MatchRules: []routing.SettingMatchRule{},
					},
				},
				Topics: []routing.Topic{
					{Type: "repository", Value: "1"},
				},
				CustomFields: []routing.CustomField{
					{
						Name:  "delivery_group",
						Value: "issues",
					},
				},
			},
			Timestamps: ts,
		},
	}

	expectedToDelete := []int64{
		1,
	}

	routingSettingsServiceMock.
		On("BatchCreateAndDelete", mock.Anything, expectedToCreate, expectedToDelete).
		Return(expectedToCreate, nil)

	s := NewServer(routingSettingsServiceMock, logs.NullTelem, stats.NullStatter, clock)

	toCreate := []*pb.CreateRequest{
		{
			UserId:   1,
			Name:     "Test settings 1",
			Channels: []*pb.Channel{{Name: "EMAIL", Enabled: true}, {Name: "PUSH", Enabled: true}},
			Topics:   []*pb.Topic{{Type: "repository", Value: "1"}},
			Filters: []*pb.Filter{{
				Reason:      "ci_activity",
				Trigger:     "created",
				SubjectType: "CheckSuite",
				MatchRules: []*pb.MatchRule{
					{
						Attribute: "failed",
						Value:     "true",
						MatchRule: "eq",
					},
				},
			}},
			CustomFields: []*pb.CustomField{{Name: "delivery_group", Value: "ci_activity"}},
		},
		{
			UserId:       2,
			Name:         "Test settings 2",
			Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: false}, {Name: "PUSH", Enabled: true}},
			Topics:       []*pb.Topic{{Type: "repository", Value: "1"}},
			Filters:      []*pb.Filter{{Reason: "ci_activity"}},
			CustomFields: []*pb.CustomField{{Name: "delivery_group", Value: "issues"}},
		},
	}

	toDelete := []*pb.DeleteRequest{
		{
			Id: 1,
		},
	}

	request := pb.BatchCreateAndDeleteRequest{
		ToDelete: toDelete,
		ToCreate: toCreate,
	}

	response, err := s.BatchCreateAndDelete(context.Background(), &request)
	suite.Require().NoError(err)
	suite.Require().NotEmpty(response.CreatedIds)
}

func (suite *suite) TestBatchCreateAndDelete_Unit_Error() {
	clock := clockpkg.NewMock()

	routingSettingsServiceMock := new(routing.ServiceMock)

	routingSettingsServiceMock.
		On("BatchCreateAndDelete", mock.Anything, mock.Anything, mock.Anything).
		Return(nil, errors.New("internal error"))

	s := NewServer(routingSettingsServiceMock, logs.NullTelem, stats.NullStatter, clock)

	toCreate := []*pb.CreateRequest{
		{
			UserId:       1,
			Name:         "Test settings 1",
			Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
			Topics:       []*pb.Topic{{Type: "repository", Value: "1"}},
			Filters:      []*pb.Filter{{Reason: "ci_activity"}},
			CustomFields: []*pb.CustomField{{Name: "delivery_group", Value: "ci_activity"}},
		},
		{
			UserId:       2,
			Name:         "Test settings 2",
			Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: false}},
			Topics:       []*pb.Topic{{Type: "repository", Value: "1"}},
			Filters:      []*pb.Filter{{Reason: "ci_activity"}},
			CustomFields: []*pb.CustomField{{Name: "delivery_group", Value: "issues"}},
		},
	}

	toDelete := []*pb.DeleteRequest{
		{
			Id: 1,
		},
	}

	request := pb.BatchCreateAndDeleteRequest{
		ToDelete: toDelete,
		ToCreate: toCreate,
	}

	_, err := s.BatchCreateAndDelete(context.Background(), &request)

	// Check that internal errors are hidden
	suite.Require().Error(err)
	suite.Require().ErrorContains(err, "Failed")
	suite.Require().NotContains(err.Error(), "internal error")
}

func TestServerUnitSuite(t *testing.T) {
	testsuite.Run(t, new(suite))
}
