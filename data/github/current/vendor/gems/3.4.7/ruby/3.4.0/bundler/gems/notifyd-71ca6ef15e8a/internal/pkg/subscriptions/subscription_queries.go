package subscriptions

import (
	sql "github.com/Masterminds/squirrel"
)

type subscriptionQueries struct{}

func (q subscriptionQueries) findByMetaID(metaID int64) sql.Sqlizer {
	return sql.Select("*").From("subscriptions_v2").Where(sql.Eq{"meta_id": metaID})
}

func (q subscriptionQueries) findIDsByMetaIDs(metaIDs []int64) sql.Sqlizer {
	return sql.Select("id").From("subscriptions_v2").Where(sql.Eq{"meta_id": metaIDs})
}

func (q subscriptionQueries) deleteByIDs(ids []int64) sql.Sqlizer {
	return sql.Delete("subscriptions_v2").Where(sql.Eq{"id": ids})
}

func (q subscriptionQueries) insert(subscriptions []*Subscription) sql.Sqlizer {
	query := sql.Insert("subscriptions_v2").
		Columns(
			"user_id",
			"topic_type",
			"topic_value",
			"subject_type",
			"subscriptions_v2.trigger",
			"reason",
			"meta_id",
			"created_at",
			"updated_at",
		)

	for _, subscription := range subscriptions {
		query = query.Values(
			subscription.UserID,
			subscription.TopicType,
			subscription.TopicValue,
			subscription.SubjectType,
			subscription.Trigger,
			subscription.Reason,
			subscription.MetaID,
			subscription.CreatedAt,
			subscription.UpdatedAt,
		)
	}

	return query
}
