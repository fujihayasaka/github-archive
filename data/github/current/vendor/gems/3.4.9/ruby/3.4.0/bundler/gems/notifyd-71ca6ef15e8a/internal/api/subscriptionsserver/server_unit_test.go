package subscriptionsserver

import (
	"context"
	"errors"
	"testing"

	_ "github.com/go-sql-driver/mysql"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	pb "github.com/github/notifyd/proto/services/subscriptions"

	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"
)

type SubscriptionsServerTestUnitSuite struct {
	testsuite.Suite
}

func (suite *SubscriptionsServerTestUnitSuite) TestGetSuccess_Unit_Pagination() {
	testCases := []struct {
		name                string
		requestPage         *pb.Page
		expectedRequestPage pagination.Page
		mockedReturnPages   pagination.Pages
		expectedResultPages *pb.Pages
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

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			subscriptionServiceMock := subscriptions.NewServiceMock(suite.T())
			s := NewServer(subscriptionServiceMock, logs.NullTelem)

			request := &pb.GetRequest{
				UserId: 1,
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
				Page: tc.requestPage,
			}

			subscriptionServiceMock.
				On("GetSubscriptionsForUser", mock.Anything, int64(1), []subscriptions.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedRequestPage).
				Return([]*subscriptions.MetaSubscription{}, tc.mockedReturnPages, nil)

			result, err := s.Get(context.Background(), request)
			suite.Require().NoError(err)

			if tc.expectedResultPages == nil {
				suite.Require().Nil(result.GetPages())
			} else {
				suite.Require().Equal(tc.expectedResultPages.Next, result.GetPages().GetNext())
			}
		})
	}
}

func (suite *SubscriptionsServerTestUnitSuite) TestGetSuccess_Unit_Failures() {
	testCases := []struct {
		name         string
		error        error
		errorMessage string
	}{
		{
			"page limit error",
			pagination.NewLimitExceededError(1000, 1001),
			"Requested page limit 1001 exceeds upper limit 1000",
		},
		{
			"other internal error",
			errors.New("some other internal error"),
			"Failed to get subscriptions",
		},
	}

	for _, tc := range testCases {
		suite.Run(tc.name, func() {
			subscriptionServiceMock := subscriptions.NewServiceMock(suite.T())
			s := NewServer(subscriptionServiceMock, logs.NullTelem)

			request := &pb.GetRequest{
				UserId: 1,
				FilterByCustomFields: []*pb.CustomField{
					{Name: "repository_id", Value: "123"},
				},
				Page: nil,
			}

			subscriptionServiceMock.
				On("GetSubscriptionsForUser", mock.Anything, int64(1), []subscriptions.CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, pagination.NewNoLimitPage()). // TODO: Update with first page after pagination is implemented on the monolith
				Return(nil, pagination.NewEmptyStandardPages(), tc.error)

			result, err := s.Get(context.Background(), request)
			suite.Require().ErrorContains(err, tc.errorMessage)
			suite.Require().Nil(result.GetPages())
		})
	}
}

func TestSubscriptionsServerTestUnitSuite(t *testing.T) {
	testsuite.Run(t, new(SubscriptionsServerTestUnitSuite))
}
