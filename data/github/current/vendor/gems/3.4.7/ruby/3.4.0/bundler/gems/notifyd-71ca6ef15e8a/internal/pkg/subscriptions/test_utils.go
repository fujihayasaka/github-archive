package subscriptions

import (
	"context"
	"sort"
	"testing"

	"github.com/Masterminds/squirrel"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/querier"
)

// AssertMetaSubscriptionsEqual performs a deep equal comparation of 2 subscriptions.
func AssertMetaSubscriptionsEqual(t *testing.T, expectedSubscription, savedSubscription *MetaSubscription) {
	t.Helper()
	r := require.New(t)

	r.Equal(expectedSubscription.UserID, savedSubscription.UserID)
	r.Equal(expectedSubscription.Details.Reason, savedSubscription.Details.Reason)

	// assert filters
	r.Len(expectedSubscription.Details.Filters, len(savedSubscription.Details.Filters))
	for filterIdx := range expectedSubscription.Details.Filters {
		expectedFilter := expectedSubscription.Details.Filters[filterIdx]
		savedFilter := savedSubscription.Details.Filters[filterIdx]

		r.Equal(expectedFilter.Trigger, savedFilter.Trigger)
		r.Equal(expectedFilter.SubjectType, savedFilter.SubjectType)

		// assert match rules
		r.Len(expectedFilter.MatchRules, len(savedFilter.MatchRules))

		for ruleIdx := range expectedFilter.MatchRules {
			r.Equal(expectedFilter.MatchRules[ruleIdx].Attribute, savedFilter.MatchRules[ruleIdx].Attribute)
			r.Equal(expectedFilter.MatchRules[ruleIdx].Value, savedFilter.MatchRules[ruleIdx].Value)
			r.Equal(expectedFilter.MatchRules[ruleIdx].MatchRule, savedFilter.MatchRules[ruleIdx].MatchRule)
		}
	}

	// assert topics
	r.Len(expectedSubscription.Details.Topics, len(savedSubscription.Details.Topics))
	for topicIdx := range expectedSubscription.Details.Topics {
		r.Equal(expectedSubscription.Details.Topics[topicIdx].Type, savedSubscription.Details.Topics[topicIdx].Type)
		r.Equal(expectedSubscription.Details.Topics[topicIdx].Value, savedSubscription.Details.Topics[topicIdx].Value)
	}

	// assert custom fields
	r.Len(expectedSubscription.Details.CustomFields, len(savedSubscription.Details.CustomFields))
	for customFieldIdx := range expectedSubscription.Details.CustomFields {
		r.Equal(expectedSubscription.Details.CustomFields[customFieldIdx].Name, savedSubscription.Details.CustomFields[customFieldIdx].Name)
		r.Equal(expectedSubscription.Details.CustomFields[customFieldIdx].Value, savedSubscription.Details.CustomFields[customFieldIdx].Value)
	}
}

func assertSubscriptionCustomFieldsAreSaved(ctx context.Context, t *testing.T, db mysql.DB, expectedSubscription, savedSubscription *MetaSubscription) {
	t.Helper()
	r := require.New(t)
	customFields := []sqlCustomField{}

	query := "select * from subscription_custom_fields where meta_id = ?"
	err := db.Read.SelectContext(ctx, &customFields, query, savedSubscription.ID)
	r.NoError(err)

	for idx, expectedField := range expectedSubscription.Details.CustomFields {
		r.Equal(expectedSubscription.UserID, customFields[idx].UserID)
		r.Equal(expectedField.Name, customFields[idx].Name)
		r.Equal(expectedField.Value, customFields[idx].Value)
	}
}

func assertInternalSubscriptionsAreSaved(ctx context.Context, t *testing.T, db mysql.DB, expectedInternalSubscriptions []*Subscription, savedSubscription *MetaSubscription) {
	t.Helper()
	r := require.New(t)

	internalSubs, err := getInternalSubscriptionsByMetaID(ctx, t, db, savedSubscription.ID)
	r.NoError(err)
	r.Len(internalSubs, len(expectedInternalSubscriptions))

	sort.Slice(internalSubs, func(i, j int) bool {
		return internalSubs[i].ID < internalSubs[j].ID
	})

	for idx, expectedSub := range expectedInternalSubscriptions {
		r.Equal(expectedSub.UserID, internalSubs[idx].UserID)
		r.Equal(expectedSub.TopicType, internalSubs[idx].TopicType)
		r.Equal(expectedSub.TopicValue, internalSubs[idx].TopicValue)
		r.Equal(expectedSub.SubjectType, internalSubs[idx].SubjectType)
		r.Equal(expectedSub.Trigger, internalSubs[idx].Trigger)

		r.Len(expectedSub.MatchRules, len(internalSubs[idx].MatchRules))

		for ruleIdx := range expectedSub.MatchRules {
			expectedRule := expectedSub.MatchRules[ruleIdx]
			rule := internalSubs[idx].MatchRules[ruleIdx]
			r.Equal(expectedRule.Attribute, rule.Attribute)
			r.Equal(expectedRule.Value, rule.Value)
			r.Equal(expectedRule.MatchRule, rule.MatchRule)
		}
	}
}

func getInternalSubscriptionsByMetaID(ctx context.Context, t *testing.T, db mysql.DB, metaID int64) ([]*Subscription, error) {
	t.Helper()

	q := querier.New()
	var subscriptions []*Subscription
	queries := subscriptionQueries{}

	if err := q.Select(ctx, db.Read, &subscriptions, queries.findByMetaID(metaID)); err != nil {
		return subscriptions, err
	}

	if len(subscriptions) == 0 {
		return subscriptions, nil
	}

	subscriptionsMap := map[int64]*Subscription{}
	var subscriptionIDs []int64
	for _, subscription := range subscriptions {
		subscriptionIDs = append(subscriptionIDs, subscription.ID)
		subscriptionsMap[subscription.ID] = subscription
	}

	var matchRules []MatchRule
	mrQuery := squirrel.Select("*").From("subscription_match_rules").Where(squirrel.Eq{"subscription_id": subscriptionIDs})
	if err := q.Select(ctx, db.Read, &matchRules, mrQuery); err != nil {
		return subscriptions, err
	}

	for _, matchRule := range matchRules {
		subscriptionsMap[matchRule.SubscriptionID].MatchRules = append(subscriptionsMap[matchRule.SubscriptionID].MatchRules, matchRule)
	}

	var subscriptionsWithMatchRules []*Subscription
	for _, subscription := range subscriptionsMap {
		subscriptionsWithMatchRules = append(subscriptionsWithMatchRules, subscription)
	}

	return subscriptionsWithMatchRules, nil
}
