package matchengine

import (
	sql "github.com/Masterminds/squirrel"

	"github.com/github/notifyd/internal/pkg/mysql/query"
	"github.com/github/notifyd/internal/pkg/notify"
)

type matchedEntriesQueries struct{}

func (q matchedEntriesQueries) findByFields(matchFields notify.MessageMatchFields) sql.Sqlizer {
	filterByTopics := sql.Or{}
	for _, topic := range matchFields.Topics {
		condition := sql.And{
			sql.Eq{"subscriptions_v2.topic_type": topic.Type},
			sql.Eq{"subscriptions_v2.topic_value": topic.Value},
		}
		filterByTopics = append(filterByTopics, condition)
	}

	filterBySubjectAndTrigger := sql.Or{
		sql.And{sql.Eq{"subscriptions_v2.subject_type": "any"}, sql.Eq{"subscriptions_v2.trigger": "any"}},
		sql.And{sql.Eq{"subscriptions_v2.subject_type": matchFields.SubjectType}, sql.Eq{"subscriptions_v2.trigger": "any"}},
		sql.And{sql.Eq{"subscriptions_v2.subject_type": matchFields.SubjectType}, sql.Eq{"subscriptions_v2.trigger": matchFields.Trigger}},
	}

	filterByMatchRules := sql.Or{query.IsNull("subscription_match_rules.subscription_id")}
	for _, rule := range matchFields.Attributes {
		expr := sql.And{
			sql.Eq{"subscription_match_rules.attribute": rule.Name},
			sql.Or{
				sql.Eq{"subscription_match_rules.value": rule.Value},
				sql.NotEq{"subscription_match_rules.match": "eq"},
			},
		}

		filterByMatchRules = append(filterByMatchRules, expr)
	}

	subquery := sql.
		Select("subscriptions_v2.id", "user_id", "reason").
		From("subscriptions_v2").
		LeftJoin("subscription_match_rules ON subscriptions_v2.id = `subscription_match_rules`.subscription_id").
		Where(filterByTopics).
		Where(filterBySubjectAndTrigger).
		Where(filterByMatchRules)

	return sql.
		Select(
			"pre_selected_subscriptions.id AS ref_id",
			"pre_selected_subscriptions.user_id",
			"pre_selected_subscriptions.reason",
			"subscription_match_rules.attribute",
			"subscription_match_rules.value",
			"subscription_match_rules.`match` AS match_rule",
		).
		FromSelect(subquery, "pre_selected_subscriptions").
		LeftJoin("subscription_match_rules ON pre_selected_subscriptions.id = `subscription_match_rules`.subscription_id")
}
