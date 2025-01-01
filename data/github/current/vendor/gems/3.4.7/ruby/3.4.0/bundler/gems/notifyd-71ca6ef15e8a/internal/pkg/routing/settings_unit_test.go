package routing

import (
	"context"
	"testing"

	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/go-stats"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
)

type serviceUnitSuite struct {
	suite.Suite
}

func (s *serviceUnitSuite) Test_Service_Unit_GetSettings() {
	testCases := []struct {
		name          string
		page          pagination.Page
		expectedPage  pagination.Page
		pages         pagination.Pages
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
			store := NewStorageMock(s.T())
			service := NewSettingsService(store, logs.NullTelem, stats.NullStatter)

			if tc.expectedError == nil {
				store.On("GetSettings", mock.Anything, []CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
					Return(nil, tc.pages, nil)
			}

			_, pages, err := service.GetSettings(
				context.Background(),
				[]CustomField{{Name: "repository_id", Value: "123"}},
				tc.page,
			)

			if tc.expectedError != nil {
				s.Require().EqualError(err, tc.expectedError.Error())
			} else {
				s.Require().NoError(err)
			}
			s.Require().Equal(tc.pages, pages)
		})
	}
}

func (s *serviceUnitSuite) Test_Service_Unit_GetSettingsForUsers() {
	testCases := []struct {
		name          string
		page          pagination.Page
		expectedPage  pagination.Page
		pages         pagination.Pages
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
			store := NewStorageMock(s.T())
			service := NewSettingsService(store, logs.NullTelem, stats.NullStatter)

			if tc.expectedError == nil {
				store.On("GetSettingsForUsers", mock.Anything, []int64{1}, []CustomField{{
					Name:  "repository_id",
					Value: "123",
				}}, tc.expectedPage).
					Return(nil, tc.pages, nil)
			}

			_, pages, err := service.GetSettingsForUsers(
				context.Background(),
				[]int64{1},
				[]CustomField{{Name: "repository_id", Value: "123"}},
				tc.page,
			)

			if tc.expectedError != nil {
				s.Require().EqualError(err, tc.expectedError.Error())
			} else {
				s.Require().NoError(err)
			}
			s.Require().Equal(tc.pages, pages)
		})
	}
}

func Test_ServiceUnitSuite(t *testing.T) {
	suite.Run(t, new(serviceUnitSuite))
}
