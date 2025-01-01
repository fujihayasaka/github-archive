package subscriptions

import (
	"context"
	"encoding/base64"
	"fmt"
	"sort"
	"strconv"
	"testing"

	sql "github.com/Masterminds/squirrel"
	"github.com/benbjohnson/clock"
	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/pagination"
)

type StorageSuite struct {
	suite.Suite
	testhelper.DatabaseSuite
}

func storageFixtures(prefix string, seqIDs *testhelper.SequentialIDs) []*MetaSubscription {
	return []*MetaSubscription{
		{
			UserID: seqIDs.GetRef(prefix + "user1"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
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
					{Type: "repository", Value: "123"},
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
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "123"},
				},
			},
		},
		{
			UserID: seqIDs.GetRef(prefix + "user1"),
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "124"},
				},
				CustomFields: []CustomField{
					{Name: "repository_id", Value: "124"},
				},
			},
		},
	}
}

func (s *StorageSuite) Test_storage_GetSubscriptions() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() Storage {
		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)

		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		return storage
	}

	tests := []struct {
		name         string
		fixtures     []*MetaSubscription
		userID       int64
		customFields []CustomField
		pagination   pagination.Page
		expected     []*MetaSubscription
	}{
		{
			name:         "fetches one subscription (filtered by two custom fields)",
			userID:       seqIDs.GetRef("1get-user1"),
			fixtures:     storageFixtures("1get-", seqIDs),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			expected:     []*MetaSubscription{storageFixtures("1get-", seqIDs)[0]},
		},
		{
			name:         "fetches three subscriptions from two different users (filtered by one custom field)",
			userID:       seqIDs.GetRef("2get-user1"),
			fixtures:     storageFixtures("2get-", seqIDs),
			customFields: []CustomField{{Name: "repository_id", Value: "123"}},
			expected:     storageFixtures("2get-", seqIDs)[0:3],
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			r := s.Require()
			storage := setup()

			_, err := storage.BatchReplace(ctx, test.userID, test.fixtures, nil)
			r.NoError(err)

			subscriptions, pages, err := storage.GetSubscriptions(ctx, test.customFields, pagination.NewStandardFirstPage())
			r.NoError(err)

			// Ensure that cursor is not returned on last page
			r.False(pages.ReturnNextCursor())

			r.Len(subscriptions, len(test.expected))

			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].ID < subscriptions[j].ID
			})

			for idx := range test.expected {
				r.Equal(len(test.expected[idx].Details.CustomFields), len(subscriptions[idx].Details.CustomFields), "Custom field length doesn't match")
			}
		})
	}
}

func (s *StorageSuite) Test_storage_GetSubscriptions_Pagination() {
	setup := func() Storage {
		s.T().Helper()

		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		db := s.DB()
		err := testhelper.TruncateTables(context.Background(), db, tables)
		s.Require().NoError(err)
		return NewStorage(clock.NewMock(), logs.NullTelem, db)
	}

	seqIDs := s.SequentialIDs()
	userID := seqIDs.GetRef("user1")

	var fixtures []*MetaSubscription
	for i := 1; i <= 10; i++ {
		fixtures = append(fixtures, &MetaSubscription{
			ID:     int64(i),
			UserID: userID,
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		})
	}

	tcs := []struct {
		name                  string
		expectedSubscriptions []*MetaSubscription
		page                  pagination.Page
		expectedPages         pagination.Pages
	}{
		{
			name:                  "no pagination: fetches all subscriptions, no next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewNoLimitPage(),
			expectedPages:         pagination.NewEmptyStandardPages(),
		},
		{
			name:                  "pagination with higher limit than results: fetches all subscriptions, no next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewStandardPage("", 20),
			expectedPages:         pagination.NewEmptyStandardPages(),
		},
		{
			name:                  "pagination with equal limit than results: fetches all subscriptions, next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewStandardPage("", 10),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"10"}`))),
		},
		{
			name:                  "pagination with smaller limit than results: fetches first subscriptions, next cursor",
			expectedSubscriptions: fixtures[:5],
			page:                  pagination.NewStandardPage("", 5),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`))),
		},
		{
			name:                  "pagination with smaller limit than results and a cursor: fetches intermediate subscriptions, next cursor",
			expectedSubscriptions: fixtures[5:9],
			page:                  pagination.NewStandardPage(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`)), 4),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"9"}`))),
		},
	}

	for _, tc := range tcs {
		s.Run(tc.name, func() {
			storage := setup()

			_, err := storage.BatchReplace(context.Background(), userID, fixtures, nil)
			s.Require().NoError(err)

			subscriptions, pages, err := storage.GetSubscriptionsForUser(
				context.Background(),
				seqIDs.GetRef("user1"),
				[]CustomField{{Name: "repository_id", Value: "123"}},
				tc.page,
			)
			s.Require().NoError(err)
			s.Require().Len(subscriptions, len(tc.expectedSubscriptions))
			s.Require().Equal(tc.expectedPages.NextCursor(), pages.NextCursor())

			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].ID < subscriptions[j].ID
			})

			for i, subscription := range subscriptions {
				id := 0
				if tc.page.Cursor() != "" {
					id, _ = strconv.Atoi(pagination.DecodeCursor(tc.page.Cursor()))
				}
				s.Require().Equal(int64(id+i+1), subscription.ID)
			}
		})
	}
}

func (s *StorageSuite) Test_storage_GetSubscriptionsForUser() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() Storage {
		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)

		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		return storage
	}

	tests := []struct {
		name       string
		existing   []*MetaSubscription
		userID     int64
		fields     []CustomField
		pagination pagination.Page
		expected   []*MetaSubscription
	}{
		{
			name:     "fetches one subscription (filtered by two custom fields)",
			userID:   seqIDs.GetRef("1get-user1"),
			existing: storageFixtures("1get-", seqIDs),
			fields:   []CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id"}},
			expected: []*MetaSubscription{storageFixtures("1get-", seqIDs)[0]},
		},
		{
			name:     "fetches two subscriptions (filtered by one custom field)",
			userID:   seqIDs.GetRef("2get-user1"),
			existing: storageFixtures("2get-", seqIDs),
			fields:   []CustomField{{Name: "repository_id", Value: "123"}},
			expected: storageFixtures("2get-", seqIDs)[0:2],
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			r := s.Require()
			storage := setup()

			_, err := storage.BatchReplace(ctx, test.userID, test.existing, nil)
			r.NoError(err)

			subscriptions, pages, err := storage.GetSubscriptionsForUser(ctx, test.userID, test.fields, pagination.NewStandardFirstPage())
			r.NoError(err)

			// Ensure that cursor is not returned on last page
			r.False(pages.ReturnNextCursor())

			r.Len(subscriptions, len(test.expected))

			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].ID < subscriptions[j].ID
			})

			for idx := range test.expected {
				r.Equal(test.expected[idx].UserID, subscriptions[idx].UserID, "User IDs don't match")
				r.Equal(len(test.expected[idx].Details.CustomFields), len(subscriptions[idx].Details.CustomFields), "Custom field length doesn't match")
			}
		})
	}
}

func (s *StorageSuite) Test_storage_GetSubscriptionsForUser_Pagination() {
	setup := func() Storage {
		s.T().Helper()

		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		db := s.DB()
		err := testhelper.TruncateTables(context.Background(), db, tables)
		s.Require().NoError(err)
		return NewStorage(clock.NewMock(), logs.NullTelem, db)
	}

	seqIDs := s.SequentialIDs()
	userID := seqIDs.GetRef("user1")

	var fixtures []*MetaSubscription
	for i := 1; i <= 10; i++ {
		fixtures = append(fixtures, &MetaSubscription{
			ID:     int64(i),
			UserID: userID,
			Details: Details{
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				CustomFields: []CustomField{
					{Name: "label_id", Value: "1"},
					{Name: "repository_id", Value: "123"},
				},
			},
		})
	}

	tcs := []struct {
		name                  string
		expectedSubscriptions []*MetaSubscription
		page                  pagination.Page
		expectedPages         pagination.Pages
	}{
		{
			name:                  "no pagination: fetches all subscriptions, no next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewNoLimitPage(),
			expectedPages:         pagination.NewEmptyStandardPages(),
		},
		{
			name:                  "pagination with higher limit than results: fetches all subscriptions, no next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewStandardPage("", 20),
			expectedPages:         pagination.NewEmptyStandardPages(),
		},
		{
			name:                  "pagination with equal limit than results: fetches all subscriptions, next cursor",
			expectedSubscriptions: fixtures,
			page:                  pagination.NewStandardPage("", 10),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"10"}`))),
		},
		{
			name:                  "pagination with smaller limit than results: fetches first subscriptions, next cursor",
			expectedSubscriptions: fixtures[:5],
			page:                  pagination.NewStandardPage("", 5),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`))),
		},
		{
			name:                  "pagination with smaller limit than results and a cursor: fetches intermediate subscriptions, next cursor",
			expectedSubscriptions: fixtures[5:9],
			page:                  pagination.NewStandardPage(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"5"}`)), 4),
			expectedPages:         pagination.NewStandardPages(base64.StdEncoding.EncodeToString([]byte(`{"v":1,"id":"9"}`))),
		},
	}
	for _, tc := range tcs {
		s.Run(tc.name, func() {
			storage := setup()

			_, err := storage.BatchReplace(context.Background(), userID, fixtures, nil)
			s.Require().NoError(err)

			subscriptions, pages, err := storage.GetSubscriptionsForUser(
				context.Background(),
				seqIDs.GetRef("user1"),
				[]CustomField{{Name: "repository_id", Value: "123"}},
				tc.page,
			)
			s.Require().NoError(err)
			s.Require().Len(subscriptions, len(tc.expectedSubscriptions))
			s.Require().Equal(tc.expectedPages.NextCursor(), pages.NextCursor())

			sort.Slice(subscriptions, func(i, j int) bool {
				return subscriptions[i].ID < subscriptions[j].ID
			})

			for i, subscription := range subscriptions {
				id := 0
				if tc.page.Cursor() != "" {
					id, _ = strconv.Atoi(pagination.DecodeCursor(tc.page.Cursor()))
				}
				s.Require().Equal(int64(id+i+1), subscription.ID)
			}
		})
	}
}

func (s *StorageSuite) Test_storage_BatchReplace() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() Storage {
		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		return storage
	}

	testCases := []struct {
		name                               string
		userID                             int64
		existingSubscriptions              []*MetaSubscription
		subscriptionsToCreate              []*MetaSubscription
		fields                             []CustomField
		expectedSubscriptionsCount         int
		expectedInternalSubscriptionsCount int
	}{
		{
			name:                  "Create Subscriptions with no replacements",
			userID:                seqIDs.GetRef("1d-user1"),
			existingSubscriptions: []*MetaSubscription{},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("1d-user1"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			fields:                             []CustomField{},
			expectedSubscriptionsCount:         1,
			expectedInternalSubscriptionsCount: 4,
		},
		{
			name:   "doesn't replace a user's subscriptions when the custom field is different",
			userID: seqIDs.GetRef("2d-user2"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("2d-user2"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("2d-user2"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual", Value: "true"},
			},
			expectedSubscriptionsCount:         2,
			expectedInternalSubscriptionsCount: 5,
		},
		{
			name:   "replaces user's subscriptions when the custom field matches",
			userID: seqIDs.GetRef("3d-user3"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("3d-user3"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("3d-user3"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "manual", Value: "false"}},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual", Value: "false"},
			},
			expectedSubscriptionsCount:         1,
			expectedInternalSubscriptionsCount: 4,
		},
		{
			name:   "does not replace a user's subscriptions when empty custom fields are given",
			userID: seqIDs.GetRef("4d-user4"),

			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("4d-user4"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("4d-user4"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
					},
				},
			},
			fields:                             []CustomField{},
			expectedSubscriptionsCount:         2,
			expectedInternalSubscriptionsCount: 5,
		},
		{
			name:   "replaces any user's subscriptions that match ALL custom field",
			userID: seqIDs.GetRef("5d-user5"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
				{
					UserID: seqIDs.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"}},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("5d-user5"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSubscriptionsCount:         1,
			expectedInternalSubscriptionsCount: 4,
		},
		{
			name:   "does not replace user's subscriptions if they don't match ALL custom field",
			userID: seqIDs.GetRef("6d-user6"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
						},
					},
				},
				{
					UserID: seqIDs.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("6d-user6"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSubscriptionsCount:         3,
			expectedInternalSubscriptionsCount: 6,
		},
		{
			name:   "replaces user's subscriptions that match the custom field name when the custom field name matches and value is left empty",
			userID: seqIDs.GetRef("1d-user7"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("1d-user7"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("1d-user7"),
					Name:   "Test sub replace",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "manual", Value: "false"}},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual"},
			},
			expectedSubscriptionsCount:         1,
			expectedInternalSubscriptionsCount: 4,
		},
		{
			name:   "deletes subscriptions if no new ones are given",
			userID: seqIDs.GetRef("1d-user8"),
			existingSubscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("1d-user8"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			subscriptionsToCreate: []*MetaSubscription{},
			fields: []CustomField{
				{Name: "manual"},
			},
			expectedSubscriptionsCount:         0,
			expectedInternalSubscriptionsCount: 0,
		},
	}
	for _, test := range testCases {
		s.Run(test.name, func() {
			r := s.Require()
			storage := setup()

			// Create existing subscriptions
			if len(test.existingSubscriptions) > 0 {
				_, err := storage.BatchReplace(ctx, test.userID, test.existingSubscriptions, []CustomField{})
				r.NoError(err)
			}

			// Replace subscriptions
			createdSubscriptionIDs, err := storage.BatchReplace(ctx, test.userID, test.subscriptionsToCreate, test.fields)
			r.NoError(err)
			r.Equal(len(createdSubscriptionIDs), len(test.subscriptionsToCreate))

			// Validate correct subscriptions and internal subscriptions created and replaced
			userSubscriptions, _, err := storage.GetSubscriptionsForUser(ctx, test.userID, []CustomField{}, pagination.NewStandardFirstPage())
			r.NoError(err)
			r.Len(userSubscriptions, test.expectedSubscriptionsCount)

			internalSubscriptionCount := 0
			for _, userSubscription := range userSubscriptions {
				userInternalSubscriptions, err := getInternalSubscriptionsByMetaID(ctx, s.T(), s.DB(), userSubscription.ID)
				internalSubscriptionCount += len(userInternalSubscriptions)
				r.NoError(err)
			}
			r.Equal(test.expectedInternalSubscriptionsCount, internalSubscriptionCount)
		})
	}
}

func (s *StorageSuite) Test_storage_BatchReplace_Details() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()
	storage := NewStorage(clock.NewMock(), logs.NullTelem, db)

	unrelatedUserSubscriptions := []*MetaSubscription{{
		UserID: seqIDs.GetRef("1f-user1"),
		Name:   "Test sub 1",
		Details: Details{
			Reason: "subscribed",
			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []Filter{
				{
					SubjectType: "issue",
					Trigger:     "created",
					MatchRules: []MatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
				{Name: "replace", Value: "true"},
			},
		},
	}}

	unrelatedUserInternalSubscriptions := []*Subscription{
		{
			UserID:      seqIDs.GetRef("1f-user1"),
			TopicType:   "repository",
			TopicValue:  "123",
			SubjectType: "issue",
			Trigger:     "created",
			MetaID:      1,
			MatchRules: []MatchRule{
				{Attribute: "has_label", Value: "1", MatchRule: "list"},
				{Attribute: "title", Value: "sub", MatchRule: "contains"},
			},
		},
	}

	subscriptionsToReplace := []*MetaSubscription{{
		UserID: seqIDs.GetRef("1f-user2"),
		Name:   "Test sub 1",
		Details: Details{
			Reason: "subscribed",
			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []Filter{
				{
					SubjectType: "issue",
					Trigger:     "created",
					MatchRules: []MatchRule{
						{Attribute: "has_label", Value: "1", MatchRule: "list"},
						{Attribute: "title", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
				{Name: "replace", Value: "true"},
			},
		},
	}}

	replacementSubscriptions := []*MetaSubscription{{
		UserID: seqIDs.GetRef("1f-user2"),
		Name:   "Test sub 1",
		Details: Details{
			Reason: "subscribed",
			Topics: []Topic{
				{Type: "repository", Value: "123"},
			},
			Filters: []Filter{
				{
					SubjectType: "pull_request",
					Trigger:     "updated",
					MatchRules: []MatchRule{
						{Attribute: "has_label", Value: "2", MatchRule: "list"},
						{Attribute: "body", Value: "sub", MatchRule: "contains"},
					},
				},
			},
			CustomFields: []CustomField{
				{Name: "repository_id", Value: "123"},
			},
		},
	}}

	replacementInternalSubscriptions := []*Subscription{
		{
			UserID:      seqIDs.GetRef("1f-user2"),
			TopicType:   "repository",
			TopicValue:  "123",
			SubjectType: "pull_request",
			Trigger:     "updated",
			MetaID:      1,
			MatchRules: []MatchRule{
				{Attribute: "has_label", Value: "2", MatchRule: "list"},
				{Attribute: "body", Value: "sub", MatchRule: "contains"},
			},
		},
	}

	s.Run("correctly replaces fields", func() {
		r := s.Require()
		unrelatedUserID := unrelatedUserSubscriptions[0].UserID

		createdUnrelatedUserSubscriptionIDs, err := storage.BatchReplace(ctx, unrelatedUserID, unrelatedUserSubscriptions, []CustomField{})
		r.NoError(err)
		r.Len(createdUnrelatedUserSubscriptionIDs, 1)

		subscriptionsToReplaceUserID := subscriptionsToReplace[0].UserID
		r.NotEqual(subscriptionsToReplaceUserID, createdUnrelatedUserSubscriptionIDs)

		savedSubscriptionToReplaceIDs, err := storage.BatchReplace(ctx, subscriptionsToReplaceUserID, subscriptionsToReplace, []CustomField{})
		r.NoError(err)
		r.Len(savedSubscriptionToReplaceIDs, 1)
		savedSubscriptionToReplace, _, err := storage.GetSubscriptionsForUser(ctx, subscriptionsToReplace[0].UserID, []CustomField{}, pagination.NewStandardFirstPage())
		r.NoError(err)
		r.Len(savedSubscriptionToReplace, 1)
		savedInternalSubscriptionToReplace, err := getInternalSubscriptionsByMetaID(ctx, s.T(), s.DB(), savedSubscriptionToReplaceIDs[0])
		r.NoError(err)
		r.Len(savedInternalSubscriptionToReplace, 1)

		replacementUserID := replacementSubscriptions[0].UserID
		r.Equal(subscriptionsToReplaceUserID, replacementUserID)
		createdSubscriptionIDs, err := storage.BatchReplace(ctx, replacementUserID, replacementSubscriptions, []CustomField{{Name: "replace", Value: "true"}})
		r.NoError(err)
		r.Len(createdSubscriptionIDs, 1)

		// Validate unrelated user subscriptions and internal subscriptions not deleted
		savedUnrelatedUserSubscriptions, _, err := storage.GetSubscriptionsForUser(ctx, unrelatedUserID, []CustomField{}, pagination.NewStandardFirstPage())
		r.NoError(err)
		r.Equal(len(savedUnrelatedUserSubscriptions), len(unrelatedUserSubscriptions))
		AssertMetaSubscriptionsEqual(s.T(), unrelatedUserSubscriptions[0], savedUnrelatedUserSubscriptions[0])
		assertSubscriptionCustomFieldsAreSaved(ctx, s.T(), s.DB(), unrelatedUserSubscriptions[0], savedUnrelatedUserSubscriptions[0])
		assertInternalSubscriptionsAreSaved(ctx, s.T(), s.DB(), unrelatedUserInternalSubscriptions, savedUnrelatedUserSubscriptions[0])

		// Validate user subscriptions and internal subscriptions are correctly replaced
		savedSubscriptions, _, err := storage.GetSubscriptionsForUser(ctx, replacementUserID, []CustomField{}, pagination.NewStandardFirstPage())
		r.NoError(err)
		r.Equal(len(savedSubscriptions), len(replacementSubscriptions))
		AssertMetaSubscriptionsEqual(s.T(), savedSubscriptions[0], replacementSubscriptions[0])
		assertSubscriptionCustomFieldsAreSaved(ctx, s.T(), s.DB(), savedSubscriptions[0], replacementSubscriptions[0])
		assertInternalSubscriptionsAreSaved(ctx, s.T(), s.DB(), replacementInternalSubscriptions, savedSubscriptions[0])

		// Validate replaced internal subscription are deleted
		foundInternalSubscriptionToReplace, err := getInternalSubscriptionsByMetaID(ctx, s.T(), s.DB(), savedSubscriptionToReplaceIDs[0])
		r.NoError(err)
		r.Empty(foundInternalSubscriptionToReplace)
	})
}

func (s *StorageSuite) Test_storage_Delete() {
	ctx := context.Background()
	db := s.DB()
	seqIDs := s.SequentialIDs()

	setup := func() Storage {
		storage := NewStorage(clock.NewMock(), logs.NullTelem, db)
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		return storage
	}

	testCases := []struct {
		name                  string
		userID                int64
		subscriptions         []*MetaSubscription
		fields                []CustomField
		expectedSubscriptions int
		expectedCustomFields  int
	}{
		{
			name:   "doesn't delete a user's subscriptions when the custom field is different",
			userID: seqIDs.GetRef("2d-user2"),
			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("2d-user2"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual", Value: "true"},
			},
			expectedSubscriptions: 1,
			expectedCustomFields:  2,
		},
		{
			name:   "deletes user's subscriptions when the custom field matches",
			userID: seqIDs.GetRef("3d-user3"),
			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("3d-user3"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual", Value: "false"},
			},
			expectedSubscriptions: 0,
			expectedCustomFields:  0,
		},
		{
			name:   "does not delete a user's subscriptions when empty custom fields are given",
			userID: seqIDs.GetRef("4d-user4"),

			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("4d-user4"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			fields:                []CustomField{},
			expectedSubscriptions: 1,
			expectedCustomFields:  2,
		},
		{
			name:   "delete any user's subscriptions that match ALL custom field",
			userID: seqIDs.GetRef("5d-user5"),
			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
				{
					UserID: seqIDs.GetRef("5d-user5"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
							{Name: "manual-field-2", Value: "true"}},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSubscriptions: 0,
			expectedCustomFields:  0,
		},
		{
			name:   "does not delete user's subscriptions if they don't match ALL custom field",
			userID: seqIDs.GetRef("6d-user6"),
			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-1", Value: "true"},
						},
					},
				},
				{
					UserID: seqIDs.GetRef("6d-user6"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "3", MatchRule: "list"},
									{Attribute: "title", Value: "other", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual-field-2", Value: "true"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual-field-1", Value: "true"},
				{Name: "manual-field-2", Value: "true"},
			},
			expectedSubscriptions: 2,
			expectedCustomFields:  4,
		},
		{
			name:   "deletes user's subscriptions that match the custom field name when the custom field name matches and value is left empty",
			userID: seqIDs.GetRef("1d-user7"),
			subscriptions: []*MetaSubscription{
				{
					UserID: seqIDs.GetRef("1d-user7"),
					Name:   "Test sub 1",
					Details: Details{
						Reason: "subscribed",
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
						Filters: []Filter{
							{
								SubjectType: "pull_request",
								Trigger:     "updated",
								MatchRules: []MatchRule{
									{Attribute: "has_label", Value: "2", MatchRule: "list"},
									{Attribute: "body", Value: "sub", MatchRule: "contains"},
								},
							},
						},
						CustomFields: []CustomField{
							{Name: "repository_id", Value: "456"},
							{Name: "manual", Value: "false"},
						},
					},
				},
			},
			fields: []CustomField{
				{Name: "manual"},
			},
			expectedSubscriptions: 0,
			expectedCustomFields:  0,
		},
	}
	for _, test := range testCases {
		s.Run(test.name, func() {
			r := s.Require()
			storage := setup()

			// Create existing subscriptions
			if len(test.subscriptions) > 0 {
				_, err := storage.BatchReplace(ctx, test.userID, test.subscriptions, []CustomField{})
				r.NoError(err)
			}

			// Delete subscriptions
			err := storage.Delete(ctx, test.userID, test.fields)
			r.NoError(err)

			// Validate correct subscriptions and internal subscriptions created and replaced
			subs, _, err := storage.GetSubscriptionsForUser(ctx, test.userID, []CustomField{}, pagination.NewStandardFirstPage())
			r.NoError(err)
			r.Len(subs, test.expectedSubscriptions)

			count := 0
			for _, s := range subs {
				query, args, err := sql.Select("*").From("subscription_custom_fields").
					Where(sql.Eq{"meta_id": s.ID}).ToSql()
				r.NoError(err)
				var fields []sqlCustomField
				err = sqlx.SelectContext(ctx, db.Read, &fields, query, args...)
				r.NoError(err)

				count += len(fields)
			}
			r.Equal(test.expectedCustomFields, count)
		})
	}
}

func (s *StorageSuite) Test_storage_GetMatchingEntries() {
	ctx := context.Background()
	db := s.DB()

	setup := func() Storage {
		// This tests asserts that the matched entries are linked to the proper subscription IDs
		// We need to truncate all tables in order to have deterministic subscription IDs
		tables := []string{
			"meta_subscriptions",
			"subscriptions_v2",
			"subscription_match_rules",
			"subscription_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		return NewStorage(clock.NewMock(), logs.NullTelem, db)
	}

	subscriptionsInDatabase := []*MetaSubscription{
		// subscription with no event filter
		{
			UserID: 1,
			Details: Details{
				Reason: "subscribed",
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
			},
		},
		// subscriptions with only subject filter
		{
			UserID: 1,
			Details: Details{
				Reason: "subscribed",
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []Filter{
					{SubjectType: "Issue"},
				},
			},
		},
		{
			UserID: 3,
			Details: Details{
				Reason: "subscribed",
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []Filter{
					{SubjectType: "PullRequest"},
				},
			},
		},
		// subscription with subject and trigger filter
		{
			UserID: 1,
			Details: Details{
				Reason: "subscribed",
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []Filter{
					{SubjectType: "Issue", Trigger: "create"},
				},
			},
		},
		// subscription with subject, trigger and match rule filter
		{
			UserID: 2,
			Details: Details{
				Reason: "subscribed",
				Topics: []Topic{
					{Type: "repository", Value: "123"},
				},
				Filters: []Filter{
					{
						SubjectType: "Issue",
						Trigger:     "create",
						MatchRules: []MatchRule{
							{Attribute: "has_label", Value: "1", MatchRule: "eq"},
						},
					},
					{
						SubjectType: "Issue",
						Trigger:     "labeled",
						MatchRules: []MatchRule{
							{Attribute: "added_label", Value: "1", MatchRule: "eq"},
							{Attribute: "title", Value: "subscription", MatchRule: "contains"},
						},
					},
				},
			},
		},
	}

	tests := []struct {
		name                   string
		dbSubscriptions        []*MetaSubscription
		userID                 int64
		msgMatchFields         notify.MessageMatchFields
		expectedMatchedEntries []*matchengine.MatchedEntry
	}{
		{
			name:            "fetches all the subscriptions with given subject type and trigger",
			userID:          1,
			dbSubscriptions: subscriptionsInDatabase,
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "create",
			},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 1, RefID: 2, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 1, RefID: 4, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
			},
		},
		{
			name:            "fetches all the subscription match rules with given subject type, trigger and subscription attributes",
			userID:          1,
			dbSubscriptions: subscriptionsInDatabase,
			msgMatchFields: notify.MessageMatchFields{
				Topics:      []notify.Topic{{Type: "repository", Value: "123"}},
				SubjectType: "Issue",
				Trigger:     "labeled",
				Attributes:  []notify.Attribute{{Name: "added_label", Value: "1"}},
			},
			expectedMatchedEntries: []*matchengine.MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 1, RefID: 2, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 6, Reason: "subscribed", Attribute: "added_label", Value: "1", MatchRule: "eq"},
				{UserID: 2, RefID: 6, Reason: "subscribed", Attribute: "title", Value: "subscription", MatchRule: "contains"},
			},
		},
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			r := s.Require()
			subscriptionsDB := setup()
			_, err := subscriptionsDB.BatchReplace(ctx, test.userID, test.dbSubscriptions, nil)
			r.NoError(err)

			matchedEntries, err := subscriptionsDB.GetMatchingEntries(ctx, test.msgMatchFields)

			r.NoError(err)

			r.Len(matchedEntries, len(test.expectedMatchedEntries))

			sort.Slice(matchedEntries, func(i, j int) bool {
				if matchedEntries[i].RefID == matchedEntries[j].RefID {
					return matchedEntries[i].Attribute < matchedEntries[j].Attribute
				}
				return matchedEntries[i].RefID < matchedEntries[j].RefID
			})

			for idx := range test.expectedMatchedEntries {
				r.Equal(test.expectedMatchedEntries[idx].UserID, matchedEntries[idx].UserID)
				r.Equal(test.expectedMatchedEntries[idx].RefID, matchedEntries[idx].RefID)
				r.Equal(test.expectedMatchedEntries[idx].Reason, matchedEntries[idx].Reason)
				r.Equal(test.expectedMatchedEntries[idx].Attribute, matchedEntries[idx].Attribute)
				r.Equal(test.expectedMatchedEntries[idx].Value, matchedEntries[idx].Value)
				r.Equal(test.expectedMatchedEntries[idx].MatchRule, matchedEntries[idx].MatchRule)
			}
		})
	}
}

func Test_StorageSuite(t *testing.T) {
	suite.Run(t, new(StorageSuite))
}
