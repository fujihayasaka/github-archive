package subscriptionsserver

import (
	"context"
	"fmt"
	"sort"
	"testing"

	"github.com/benbjohnson/clock"
	_ "github.com/go-sql-driver/mysql"

	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	api_pb "github.com/github/notifyd/proto/services/subscriptions"
)

type SubscriptionsServerTestSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func TestSubscriptionsServerTestSuite(t *testing.T) {
	testsuite.Run(t, new(SubscriptionsServerTestSuite))
}

func fixtures(prefix string, sq *testhelper.SequentialIDs, clk *clock.Mock) []*subscriptions.MetaSubscription {
	return []*subscriptions.MetaSubscription{
		{
			UserID: sq.GetRef(prefix + "user1"),
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: sq.GetRef(prefix + "user1"),
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: sq.GetRef(prefix + "user1"),
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "124"},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "124"},
				},
			},
		},
		{
			UserID: sq.GetRef(prefix + "user2"),
			Details: subscriptions.Details{
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: sq.GetRef(prefix + "user3"),
			Details: subscriptions.Details{
				Reason: "subscribed",
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "321"},
				},
			},
			Timestamps: mysql.Timestamps{CreatedAt: clk.Now()},
		},
	}
}

func (suite *SubscriptionsServerTestSuite) TestGet_E2E() {
	ctx := context.Background()
	db := suite.DB()
	sq := suite.SequentialIDs()
	clk := clock.NewMock()

	setup := func() (*Server, subscriptions.Storage) {
		// This test checks for returned IDs and needs IDs for the delete operation
		// and they have to be hardcoded for the moment
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		storage := subscriptions.NewStorage(clk, logs.NullTelem, db)
		service := subscriptions.NewService(storage, logs.NullTelem, stats.NullStatter)
		server := NewServer(service, logs.NullTelem)
		return server, storage
	}

	testCases := []struct {
		name             string
		dbSubscriptions  []*subscriptions.MetaSubscription
		expectedResponse *api_pb.GetResponse
		getRequest       *api_pb.GetRequest
	}{
		{
			name: "returns response with subscriptions",
			getRequest: &api_pb.GetRequest{
				UserId:               sq.GetRefInt32("1get-user1"),
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
			},
			dbSubscriptions: fixtures("1get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("1get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("1get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name: "returns response with subscriptions filter by multiple fields",
			getRequest: &api_pb.GetRequest{
				UserId:               sq.GetRefInt32("2get-user1"),
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			},
			dbSubscriptions: fixtures("2get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("2get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name: "returns response with subscriptions without filtering but limited by pagination",
			getRequest: &api_pb.GetRequest{
				UserId: sq.GetRefInt32("3get-user1"),
				Page:   &api_pb.Page{Limit: int64(2)},
			},
			dbSubscriptions: fixtures("3get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("3get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("3get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name: "returns response with reasons and created_at fields",
			getRequest: &api_pb.GetRequest{
				UserId: sq.GetRefInt32("5get-user3"),
			},
			dbSubscriptions: fixtures("5get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:    sq.GetRefInt32("5get-user3"),
						Reason:    "subscribed",
						CreatedAt: clk.Now().Unix(),
					},
				},
			},
		},
		{
			name: "returns response with subscriptions with no results",
			getRequest: &api_pb.GetRequest{
				UserId:               sq.GetRefInt32("4get-user1"),
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "5"}},
			},
			dbSubscriptions: fixtures("4get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{},
			},
		},
		{
			name: "no user: returns response with subscriptions",
			getRequest: &api_pb.GetRequest{
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
			},
			dbSubscriptions: fixtures("6get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("6get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("6get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("6get-user2"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name: "no user: returns response with subscriptions filter by multiple fields",
			getRequest: &api_pb.GetRequest{
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			},
			dbSubscriptions: fixtures("7get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("7get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("7get-user2"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name:            "no user: returns response with subscriptions without filtering but limited by pagination",
			getRequest:      &api_pb.GetRequest{Page: &api_pb.Page{Limit: int64(2)}},
			dbSubscriptions: fixtures("8get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("8get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("8get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
					},
				},
			},
		},
		{
			name:            "no user: returns response with reasons and created_at fields",
			getRequest:      &api_pb.GetRequest{},
			dbSubscriptions: fixtures("9get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{
					{
						UserId:       sq.GetRefInt32("9get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("9get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}},
					},
					{
						UserId:       sq.GetRefInt32("9get-user1"),
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "124"}},
					},
					{
						UserId:       sq.GetRefInt32("9get-user2"),
						CustomFields: []*api_pb.CustomField{{Name: "label_id", Value: "1"}, {Name: "repository_id", Value: "123"}},
					},
					{
						UserId:    sq.GetRefInt32("9get-user3"),
						Reason:    "subscribed",
						CreatedAt: clk.Now().Unix(),
					},
				},
			},
		},
		{
			name: "no user: returns response with subscriptions with no results",
			getRequest: &api_pb.GetRequest{
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "5"}},
			},
			dbSubscriptions: fixtures("10get-", sq, clk),
			expectedResponse: &api_pb.GetResponse{
				Subscriptions: []*api_pb.Subscription{},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			server, storage := setup()
			_, err := storage.BatchReplace(ctx, int64(test.getRequest.UserId), test.dbSubscriptions, nil)
			suite.Require().NoError(err)
			subscriptionsResponse, err := server.Get(ctx, test.getRequest)
			suite.Require().NoError(err)
			suite.Require().Len(subscriptionsResponse.Subscriptions, len(test.expectedResponse.Subscriptions))
			sort.Slice(subscriptionsResponse.Subscriptions, func(i, j int) bool {
				return subscriptionsResponse.Subscriptions[i].Id < subscriptionsResponse.Subscriptions[j].Id
			})

			for idx := range test.expectedResponse.Subscriptions {
				suite.Require().Equal(test.expectedResponse.Subscriptions[idx].UserId, subscriptionsResponse.Subscriptions[idx].UserId)
				for cidx := range test.expectedResponse.Subscriptions[idx].CustomFields {
					suite.Require().Equal(test.expectedResponse.Subscriptions[idx].CustomFields[cidx], subscriptionsResponse.Subscriptions[idx].CustomFields[cidx])
				}
				suite.Require().Equal(test.expectedResponse.Subscriptions[idx].Reason, subscriptionsResponse.Subscriptions[idx].Reason)
				suite.Require().Equal(test.expectedResponse.Subscriptions[idx].CreatedAt, subscriptionsResponse.Subscriptions[idx].CreatedAt)
			}
		})
	}
}

func (suite *SubscriptionsServerTestSuite) Test_BatchReplace_Integration_Success() {
	var userID int64 = 1
	ctx := context.Background()
	filters := []*api_pb.Filter{
		{
			SubjectType: "issue",
			Trigger:     "created",
			MatchRules: []*api_pb.MatchRule{
				{Attribute: "has_label", Value: "1", MatchRule: "list"},
				{Attribute: "title", Value: "sub", MatchRule: "contains"},
			},
		},
	}
	subscriptionsToCreate := []*api_pb.BatchReplaceCreateRequest{
		{
			Reason:       "subscribed",
			Topics:       []*api_pb.Topic{{Type: "repository", Value: "123"}, {Type: "repository", Value: "456"}},
			CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			Filters:      filters,
		},
	}

	fields := []*api_pb.CustomField{
		{Name: "field name 1", Value: "field value 1"},
		{Name: "field name 2", Value: "field value 2"},
	}

	batchReplaceRequest := api_pb.BatchReplaceRequest{
		UserId:                int32(userID),
		NewSubscriptions:      subscriptionsToCreate,
		ReplaceByCustomFields: fields,
	}

	expectedMetaSubscriptionToCreate := []*subscriptions.MetaSubscription{
		{
			UserID: 1,
			Details: subscriptions.Details{
				Reason: "subscribed",
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "123"}, {Type: "repository", Value: "456"},
				},
				CustomFields: []subscriptions.CustomField{
					{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"},
				},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "issue",
						Trigger:     "created",
						MatchRules: []subscriptions.MatchRule{
							{Attribute: "has_label", Value: "1", MatchRule: "list"},
							{Attribute: "title", Value: "sub", MatchRule: "contains"},
						},
					},
				},
			},
		},
	}

	expectedFields := []subscriptions.CustomField{
		{Name: "field name 1", Value: "field value 1"},
		{Name: "field name 2", Value: "field value 2"},
	}

	storage := subscriptions.NewStorageMock(suite.T())
	storage.
		On("BatchReplace", mock.Anything, userID, expectedMetaSubscriptionToCreate, expectedFields).
		Return([]int64{1}, nil)

	service := subscriptions.NewService(storage, logs.NullTelem, stats.NullStatter)
	s := NewServer(service, logs.NullTelem)

	response, err := s.BatchReplace(ctx, &batchReplaceRequest)
	suite.Require().NoError(err)
	suite.Require().Equal([]int64{1}, response.GetCreatedIds())
}

func (suite *SubscriptionsServerTestSuite) Test_BatchReplace_Integration_Failure() {
	var userID int64 = 1
	ctx := context.Background()
	filters := []*api_pb.Filter{
		{
			SubjectType: "issue",
			Trigger:     "created",
			MatchRules: []*api_pb.MatchRule{
				{Attribute: "has_label", Value: "1", MatchRule: "list"},
			},
		},
	}
	subscriptionsToCreate := []*api_pb.BatchReplaceCreateRequest{
		{
			Reason: "subscribed",
			Topics: []*api_pb.Topic{
				{Type: "repository", Value: "456"},
			},
			CustomFields: []*api_pb.CustomField{},
			Filters:      filters,
		},
	}

	fields := []*api_pb.CustomField{
		{Name: "field name 1", Value: "field value 1"},
	}

	batchReplaceRequest := api_pb.BatchReplaceRequest{
		UserId:                int32(userID),
		NewSubscriptions:      subscriptionsToCreate,
		ReplaceByCustomFields: fields,
	}

	expectedMetaSubscriptionToCreate := []*subscriptions.MetaSubscription{
		{
			UserID: userID,
			Details: subscriptions.Details{
				Reason: "subscribed",
				Topics: []subscriptions.Topic{
					{Type: "repository", Value: "456"},
				},
				CustomFields: []subscriptions.CustomField{},
				Filters: []subscriptions.Filter{
					{
						SubjectType: "issue",
						Trigger:     "created",
						MatchRules: []subscriptions.MatchRule{
							{Attribute: "has_label", Value: "1", MatchRule: "list"},
						},
					},
				},
			},
		},
	}

	expectedFields := []subscriptions.CustomField{
		{Name: "field name 1", Value: "field value 1"},
	}

	storage := subscriptions.NewStorageMock(suite.T())
	storage.
		On("BatchReplace", mock.Anything, userID, expectedMetaSubscriptionToCreate, expectedFields).
		Return([]int64{}, errors.New("internal error"))

	service := subscriptions.NewService(storage, logs.NullTelem, stats.NullStatter)
	s := NewServer(service, logs.NullTelem)

	response, err := s.BatchReplace(ctx, &batchReplaceRequest)
	suite.Require().Nil(response)
	suite.Require().Error(err)
	suite.Require().ErrorContains(err, "Failed to batch replace subscriptions")
	suite.Require().NotContains(err.Error(), "internal error")
}
