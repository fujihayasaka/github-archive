package routing

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

type SettingsServiceTestSuiteCreate struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func TestSettingsTestSuiteCreate(t *testing.T) {
	testsuite.Run(t, new(SettingsServiceTestSuiteCreate))
}

func (suite *SettingsServiceTestSuiteCreate) TestSettingsService_BatchCreateAndDelete() {
	setup := func() (SettingsService, *StorageMock) {
		store := new(StorageMock)
		service := NewSettingsService(store, logs.NullTelem, stats.NullStatter)
		return service, store
	}

	service, db := setup()
	ctx := context.Background()
	t := suite.SequentialIDs()

	toCreate := []*MetaSetting{
		{
			UserID: t.GetRef("1a-user1"),
			Name:   "Test sub 1",
			Details: SettingDetails{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
					{Type: "repository", Value: "456"},
				},
				Filters: []SettingFilter{
					{
						SubjectType: "issue",
						Trigger:     "created",
						MatchRules:  []SettingMatchRule{},
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
	}
	toDelete := []int64{
		1,
	}

	db.
		On("BatchCreateAndDelete", mock.Anything, toCreate, toDelete).
		Return(toCreate, nil)

	result, err := service.BatchCreateAndDelete(ctx, toCreate, toDelete)
	suite.Require().NoError(err)
	suite.Require().NotEmpty(result)
}

func (suite *SettingsServiceTestSuiteCreate) TestSettingsService_BatchCreateAndDelete_Error() {
	setup := func() (SettingsService, *StorageMock) {
		store := new(StorageMock)
		service := NewSettingsService(store, logs.NullTelem, stats.NullStatter)
		return service, store
	}

	service, db := setup()
	ctx := context.Background()

	toCreate := []*MetaSetting{
		{},
	}
	var toDelete []int64

	db.
		On("BatchCreateAndDelete", mock.Anything, mock.Anything, mock.Anything).
		Return(nil, errors.New("test error"))

	result, err := service.BatchCreateAndDelete(ctx, toCreate, toDelete)
	suite.Require().Nil(result)
	suite.Require().ErrorContains(err, "batch create and delete settings from database")
	suite.Require().ErrorContains(err, "test error")
}
