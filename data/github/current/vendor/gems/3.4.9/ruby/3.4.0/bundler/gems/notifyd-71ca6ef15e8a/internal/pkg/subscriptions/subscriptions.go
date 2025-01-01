package subscriptions

import (
	"github.com/github/notifyd/internal/pkg/mysql"
)

// Subscription represents a subscription.
type Subscription struct {
	ID          int64  `db:"id"`
	UserID      int64  `db:"user_id"`
	TopicType   string `db:"topic_type"`
	TopicValue  string `db:"topic_value"`
	SubjectType string `db:"subject_type"`
	Trigger     string `db:"trigger"`
	MetaID      int64  `db:"meta_id"`
	Reason      string `db:"reason"`
	MatchRules  []MatchRule
	mysql.Timestamps
}

// SetID sets the ID of the subscription.
func (s *Subscription) SetID(id int64) {
	s.ID = id
	for idx := range s.MatchRules {
		s.MatchRules[idx].SubscriptionID = id
	}
}
