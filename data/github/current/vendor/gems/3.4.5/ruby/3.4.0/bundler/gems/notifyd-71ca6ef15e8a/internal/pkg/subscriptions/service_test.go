package subscriptions

import (
	"context"
	"sort"
	"testing"

	"github.com/benbjohnson/clock"
	_ "github.com/go-sql-driver/mysql"
	"github.com/stretchr/testify/suite"

	"github.com/github/go-stats"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
)

type ServiceSuite struct {
	suite.Suite
	testhelper.DatabaseSuite
}

func serviceFixtures(prefix string, seqIDs *testhelper.SequentialIDs) []*MetaSubscription {
	return []*MetaSubscription{
		{
			UserID: seqIDs.GetRef(prefix + "user1"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "1"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: seqIDs.GetRef(prefix + "user1"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "2"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: seqIDs.GetRef(prefix + "user2"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "4"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: seqIDs.GetRef(prefix + "user1"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "3"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "124"},
				},
			},
		},
	}
}

func (s *ServiceSuite) Test_Service_E2E_GetSubscriptions() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() (Service, Storage) {
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		s.Require().NoError(err)

		store := NewStorage(clock.NewMock(), logs.NullTelem, db)
		svc := NewService(store, logs.NullTelem, stats.NullStatter)
		return svc, store
	}
	tests := []struct {
		name         string
		customFields []CustomField
		existing     []*MetaSubscription
		expected     []*MetaSubscription
	}{
		{
			name:         "returns two meta subscriptions that match custom fields",
			customFields: []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			existing:     serviceFixtures("1get-", seqIDs),
			expected:     []*MetaSubscription{serviceFixtures("1get-", seqIDs)[0], serviceFixtures("1get-", seqIDs)[2]},
		},
		{
			name:         "returns three meta subscriptions that match custom fields",
			customFields: []CustomField{{Name: "repository_id", Value: "123"}},
			existing:     serviceFixtures("2get-", seqIDs),
			expected:     serviceFixtures("2get-", seqIDs)[0:3],
		},
	}
	for _, test := range tests {
		s.Run(test.name, func() {
			r := s.Require()
			svc, store := setup()

			_, err := store.BatchReplace(ctx, 0, test.existing, nil)
			r.NoError(err)

			subscriptions, pages, err := svc.GetSubscriptions(ctx, test.customFields, pagination.NewStandardFirstPage())
			r.NoError(err)
			r.Len(subscriptions, len(test.expected))
			r.Empty(pages.NextCursor())

			// Sort by topic repository value to avoid using ids and having to truncate tables
			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].Details.Topics[0].Value < subscriptions[j].Details.Topics[0].Value
			})
			sort.Slice(test.expected, func(i, j int) bool {
				return test.expected[i].Details.Topics[0].Value < test.expected[j].Details.Topics[0].Value
			})

			for idx := range test.expected {
				r.Equal(test.expected[idx].UserID, subscriptions[idx].UserID)
				r.Equal(len(test.expected[idx].Details.Topics), len(subscriptions[idx].Details.Topics))
				r.Equal(len(test.expected[idx].Details.CustomFields), len(subscriptions[idx].Details.CustomFields))
			}
		})
	}
}

func (s *ServiceSuite) Test_Service_E2E_GetSubscriptionsForUser() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() (Service, Storage) {
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		err := testhelper.TruncateTables(ctx, db, tables)
		s.Require().NoError(err)

		store := NewStorage(clock.NewMock(), logs.NullTelem, db)
		svc := NewService(store, logs.NullTelem, stats.NullStatter)
		return svc, store
	}
	tests := []struct {
		name         string
		userID       int64
		customFields []CustomField
		existing     []*MetaSubscription
		expected     []*MetaSubscription
	}{
		{
			name:         "returns one meta subscription that match custom fields",
			userID:       seqIDs.GetRef("1get-user2"),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "1"}},
			existing:     serviceFixtures("1get-", seqIDs),
			expected:     []*MetaSubscription{serviceFixtures("1get-", seqIDs)[2]},
		},
		{
			name:         "returns two meta subscriptions that match custom fields",
			userID:       seqIDs.GetRef("2get-user1"),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}},
			existing:     serviceFixtures("2get-", seqIDs),
			expected:     serviceFixtures("2get-", seqIDs)[0:2],
		},
	}
	for _, test := range tests {
		s.Run(test.name, func() {
			r := s.Require()
			svc, store := setup()

			_, err := store.BatchReplace(ctx, test.userID, test.existing, nil)
			r.NoError(err)

			subscriptions, pages, err := svc.GetSubscriptionsForUser(ctx, test.userID, test.customFields, pagination.NewStandardFirstPage())
			r.NoError(err)
			r.Len(subscriptions, len(test.expected))
			r.Empty(pages.NextCursor())

			// Sort by topic repository value to avoid using ids and having to truncate tables
			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].Details.Topics[0].Value < subscriptions[j].Details.Topics[0].Value
			})
			sort.Slice(test.expected, func(i, j int) bool {
				return test.expected[i].Details.Topics[0].Value < test.expected[j].Details.Topics[0].Value
			})

			for idx := range test.expected {
				r.Equal(test.expected[idx].UserID, subscriptions[idx].UserID)
				r.Equal(len(test.expected[idx].Details.Topics), len(subscriptions[idx].Details.Topics))
				r.Equal(len(test.expected[idx].Details.CustomFields), len(subscriptions[idx].Details.CustomFields))
			}
		})
	}
}

func Test_ServiceSuite(t *testing.T) {
	suite.Run(t, new(ServiceSuite))
}
