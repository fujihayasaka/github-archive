package subscriptions

import (
	sql "github.com/Masterminds/squirrel"
)

type matchRulesQueries struct{}

func (q matchRulesQueries) deleteBySubscriptionIDs(subscriptionIDs []int64) sql.Sqlizer {
	return sql.Delete("subscription_match_rules").Where(sql.Eq{"subscription_id": subscriptionIDs})
}

func (q matchRulesQueries) insert(rules []MatchRule) sql.Sqlizer {
	query := sql.Insert("subscription_match_rules").
		Columns("subscription_id", "attribute", "value", "`match`", "created_at", "updated_at")

	for _, rule := range rules {
		query = query.Values(
			rule.SubscriptionID,
			rule.Attribute,
			rule.Value,
			rule.MatchRule,
			rule.CreatedAt,
			rule.UpdatedAt,
		)
	}

	return query
}
