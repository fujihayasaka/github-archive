package subscriptions

import (
	sql "github.com/Masterminds/squirrel"
)

type customFieldQueries struct{}

func (q customFieldQueries) deleteByMetaIDs(userID int64, subscriptionIDs []int64) sql.Sqlizer {
	query := sql.Delete("subscription_custom_fields")

	if userID == -1 {
		return query.Where(sql.Eq{"meta_id": subscriptionIDs})
	}
	return query.Where(sql.And{
		sql.Eq{"meta_id": subscriptionIDs},
		sql.Eq{"user_id": userID},
	})
}

func (q customFieldQueries) insert(fields []sqlCustomField) sql.Sqlizer {
	query := sql.Insert("subscription_custom_fields").
		Columns("user_id", "meta_id", "name", "value", "created_at", "updated_at")

	for _, field := range fields {
		query = query.Values(
			field.UserID,
			field.SubscriptionID,
			field.Name,
			field.Value,
			field.CreatedAt,
			field.UpdatedAt,
		)
	}

	return query
}
