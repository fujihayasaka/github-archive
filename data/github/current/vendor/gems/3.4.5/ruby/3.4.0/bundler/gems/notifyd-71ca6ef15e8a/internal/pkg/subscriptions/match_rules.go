package subscriptions

import "github.com/github/notifyd/internal/pkg/mysql"

// MatchRule represents a subscription match rule.
type MatchRule struct {
	ID             int64  `db:"id"`
	SubscriptionID int64  `db:"subscription_id"`
	Attribute      string `db:"attribute"       json:"attribute"`
	Value          string `db:"value"           json:"value"`
	MatchRule      string `db:"match"           json:"match_rule"`
	mysql.Timestamps
}

// RuleEQ returns a new rule.
func RuleEQ(attr, value string) MatchRule {
	return MatchRule{Attribute: attr, Value: value, MatchRule: "eq"}
}
