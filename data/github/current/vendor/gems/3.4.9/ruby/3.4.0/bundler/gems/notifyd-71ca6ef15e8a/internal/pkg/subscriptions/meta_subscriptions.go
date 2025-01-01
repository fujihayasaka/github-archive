package subscriptions

import (
	"database/sql/driver"
	"encoding/json"

	clockpkg "github.com/benbjohnson/clock"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
)

// MetaSubscription represents consolidated subscription data for a user.
type MetaSubscription struct {
	ID      int64   `db:"id"`
	UserID  int64   `db:"user_id"`
	Name    string  `db:"name"`
	Details Details `db:"details"`
	mysql.Timestamps
}

func (s *MetaSubscription) setID(id int64) {
	s.ID = id
}

// toSubscriptions transforms a single MetaSubscription in the group of Subscriptions that represent
// them internally together with Filters and MatchRules.
func (s *MetaSubscription) toSubscriptions(clock clockpkg.Clock) ([]*Subscription, error) {
	var subscriptions []*Subscription

	if s.ID == 0 {
		return subscriptions, errors.New("invalid subscription")
	}

	for _, topic := range s.Details.Topics {
		if len(s.Details.Filters) == 0 {
			subscription := &Subscription{
				UserID:      s.UserID,
				TopicType:   topic.Type,
				TopicValue:  topic.Value,
				SubjectType: "any",
				Trigger:     "any",
				Reason:      s.Details.Reason,
				MetaID:      s.ID,
			}

			subscription.UpdateTimestamps(clock)
			subscriptions = append(subscriptions, subscription)
			continue
		}

		for _, filter := range s.Details.Filters {
			subscription := &Subscription{
				UserID:      s.UserID,
				TopicType:   topic.Type,
				TopicValue:  topic.Value,
				SubjectType: filter.SubjectType,
				Trigger:     filter.normalizeTrigger(),
				Reason:      s.Details.Reason,
				MetaID:      s.ID,
			}

			matchRules := filter.MatchRules
			for _, rule := range matchRules {
				subscription.MatchRules = append(subscription.MatchRules, MatchRule{
					Attribute:  rule.Attribute,
					Value:      rule.Value,
					MatchRule:  rule.MatchRule,
					Timestamps: s.Timestamps,
				})
			}

			subscription.UpdateTimestamps(clock)
			subscriptions = append(subscriptions, subscription)
		}
	}

	return subscriptions, nil
}

/*
Details is a part of MetaSubscription that contain all the subscription related data in JSON format.
This data is saved to details column on meta_subscriptions and is supposed to be used for UI
and other integrator scenarios that involve API.
*/
//nolint:recvcheck // This struct must use pointer and non-pointer receivers to match interfaces.
type Details struct {
	Reason       string        `json:"reason"`
	Filters      []Filter      `json:"filters"`
	Topics       []Topic       `json:"topics"`
	CustomFields []CustomField `json:"custom_fields"`
}

// Scan implements the sql.Scanner interface. This allows us to automatically deserialize the value
// of the Details value when we read the JSON blob from the database.
func (d *Details) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &d)
	case string:
		return json.Unmarshal([]byte(v), &d)
	default:
		return errors.Newf("Unsupported type: %T", v)
	}
}

// Value implements the driver.Valuer interface. This allows us to automatically serialize the value
// of Details into JSON when it is going to be written in the database.
func (d Details) Value() (driver.Value, error) {
	bytes, err := json.Marshal(d)

	if err != nil {
		return nil, err
	}

	return string(bytes), nil
}

// Filter represents a subscription filter.
type Filter struct {
	SubjectType string      `json:"subject_type"`
	Trigger     string      `json:"trigger"`
	MatchRules  []MatchRule `json:"match_rules"`
}

func (f Filter) normalizeTrigger() string {
	if f.Trigger == "" {
		return "any"
	}

	return f.Trigger
}
