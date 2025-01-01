package subscriptions

import (
	"context"
	"testing"

	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/pagination"
)

type ServiceUnitSuite struct {
	suite.Suite
}

func (s *ServiceUnitSuite) Test_Service_Unit_GetSubscriptions() {
	testCases := []struct {
		name          string
		requestedPage pagination.Page
		expectedPage  pagination.Page
		resultPages   pagination.Pages
		expectedError error
	}{
		{
			"page limit not exceeded",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 999),
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 999),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("123")),
			nil,
		},
		{
			"page limit hit",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1000),
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1000),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("123")),
			nil,
		},
		{
			"page limit exceeded",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1001),
			nil,
			pagination.NewEmptyStandardPages(),
			pagination.NewLimitExceededError(1000, 1001),
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			storage := NewStorageMock(s.T())
			service := NewService(storage, nil, stats.NullStatter)

			if tc.expectedError == nil {
				storage.On("GetSubscriptions", mock.Anything, []CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
					Return([]*MetaSubscription{}, tc.resultPages, nil)
			}

			_, pages, err := service.GetSubscriptions(context.Background(), []CustomField{{
				Name: "repository_id", Value: "123",
			}}, tc.requestedPage)

			if tc.expectedError != nil {
				s.Require().EqualError(err, tc.expectedError.Error())
			} else {
				s.Require().NoError(err)
			}
			s.Require().Equal(tc.resultPages, pages)
		})
	}
}

func (s *ServiceUnitSuite) Test_Service_Unit_GetSubscriptionsForUser() {
	testCases := []struct {
		name          string
		requestedPage pagination.Page
		expectedPage  pagination.Page
		resultPages   pagination.Pages
		expectedError error
	}{
		{
			"page limit not exceeded",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 999),
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 999),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("123")),
			nil,
		},
		{
			"page limit hit",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1000),
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1000),
			pagination.NewStandardPages(pagination.EncodeV1Cursor("123")),
			nil,
		},
		{
			"page limit exceeded",
			pagination.NewStandardPage(pagination.EncodeV1Cursor("2"), 1001),
			nil,
			pagination.NewEmptyStandardPages(),
			pagination.NewLimitExceededError(1000, 1001),
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			storage := NewStorageMock(s.T())
			service := NewService(storage, nil, stats.NullStatter)

			if tc.expectedError == nil {
				storage.On("GetSubscriptionsForUser", mock.Anything, int64(1), []CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
					Return([]*MetaSubscription{}, tc.resultPages, nil)
			}

			_, pages, err := service.GetSubscriptionsForUser(context.Background(), int64(1), []CustomField{{
				Name: "repository_id", Value: "123",
			}}, tc.requestedPage)

			if tc.expectedError != nil {
				s.Require().EqualError(err, tc.expectedError.Error())
			} else {
				s.Require().NoError(err)
			}
			s.Require().Equal(tc.resultPages, pages)
		})
	}
}

func Test_ServiceUnitSuite(t *testing.T) {
	suite.Run(t, new(ServiceUnitSuite))
}
