package routing

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/benbjohnson/clock"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/notify"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

// Topic represents a generic way to categorize and group notifications. As an example for label
// subscriptions we group them by repository ID, so Type is `repository_id` and `Value` is the ID
// itself.
type Topic struct {
	Type, Value string
}

// Setting represents a configuration that we use in order to decide which channel we'll use to
// deliver a notification depending on whether it matches or not certain conditions like the right
// `Topic`, reason, etc.
type Setting struct {
	ID          int64  `db:"id"`
	UserID      int64  `db:"user_id"`
	TopicType   string `db:"topic_type"`
	TopicValue  string `db:"topic_value"`
	SubjectType string `db:"subject_type"`
	Trigger     string `db:"trigger"`
	MetaID      int64  `db:"meta_id"`
	Reason      string `db:"reason"`
	Notify      bool   `db:"notify"`
	MatchRules  []SettingMatchRule
	Channels    map[string]*matchengine_dto.Channel
	mysql.Timestamps
}

// MetaSetting is a denormalized representation of a Setting. They are exposed to integrators mainly
// so that they have a simpler way to interface with settings and query the right ones.
type MetaSetting struct {
	ID      int64          `db:"id"`
	UserID  int64          `db:"user_id"`
	Name    string         `db:"name"`
	Details SettingDetails `db:"details"`
	mysql.Timestamps
}

// Settings returns all the `Setting` entries associated with a `MetaSetting`. Note that the a
// single MetaSetting has many Settings.
func (m *MetaSetting) Settings(clk clock.Clock) ([]*Setting, error) {
	var routingSettings []*Setting

	if m.ID == 0 {
		return routingSettings, errors.New("invalid meta setting ID")
	}

	for _, topic := range m.Details.Topics {
		if len(m.Details.Filters) == 0 {
			routingSetting := &Setting{
				UserID:      m.UserID,
				TopicType:   topic.Type,
				TopicValue:  topic.Value,
				Notify:      false,
				SubjectType: "any",
				Trigger:     "any",
				Reason:      "any",
				MetaID:      m.ID,
				Channels:    m.Details.Channels,
			}

			routingSetting.UpdateTimestamps(clk)
			routingSettings = append(routingSettings, routingSetting)
			continue
		}

		for _, filter := range m.Details.Filters {
			var trigger string
			if filter.Trigger == "" {
				trigger = "any"
			} else {
				trigger = filter.Trigger
			}

			var subject string
			if filter.SubjectType == "" {
				subject = "any"
			} else {
				subject = filter.SubjectType
			}

			reason := filter.Reason
			if reason == "" {
				reason = "any"
			}

			routingSetting := &Setting{
				UserID:      m.UserID,
				Channels:    m.Details.Channels,
				TopicType:   topic.Type,
				TopicValue:  topic.Value,
				SubjectType: subject,
				Trigger:     trigger,
				Reason:      reason,
				MetaID:      m.ID,
			}

			matchRules := filter.MatchRules
			for _, rule := range matchRules {
				routingSetting.MatchRules = append(routingSetting.MatchRules, SettingMatchRule{
					Attribute:  rule.Attribute,
					Value:      rule.Value,
					MatchRule:  rule.MatchRule,
					Timestamps: m.Timestamps,
				})
			}

			routingSetting.UpdateTimestamps(clk)
			routingSettings = append(routingSettings, routingSetting)
		}
	}

	return routingSettings, nil
}

// SettingDetails is a part of MetaSetting that contain all the routing setting related data in JSON
// format. This data is saved to the details column on meta_routing_setting and is supposed to be
// used for UI and other integrator scenarios that involve API.
//
//nolint:recvcheck // This struct must use pointer and non-pointer receivers to match interfaces.
type SettingDetails struct {
	Channels     map[string]*matchengine_dto.Channel `json:"channels"`
	Filters      []SettingFilter                     `json:"filters"`
	Topics       []Topic                             `json:"topics"`
	CustomFields []CustomField                       `json:"custom_fields"`
}

// Scan implements the `Scanner` interface from sql.Rows, we do this so that we can unmarshal the
// JSON data stored on a `SettingDetail` when its owning `MetaSetting` is read from DB.
func (sd *SettingDetails) Scan(val interface{}) error {
	switch v := val.(type) {
	case []byte:
		return json.Unmarshal(v, &sd)
	case string:
		return json.Unmarshal([]byte(v), &sd)
	default:
		return errors.Newf("Unsupported type: %T", v)
	}
}

// Value implements the `driver.Valuer` interface. We do this so that we can serialize the JSON data
// from the `SettingDetails` when we write its parent `MetaSetting` to DB.
func (sd SettingDetails) Value() (driver.Value, error) {
	bytes, err := json.Marshal(sd)

	if err != nil {
		return nil, err
	}

	return string(bytes), nil
}

// SettingFilter defines the set of conditions we want to be met in order for a given Setting to
// match. If a `MatchQuery` fulfills the set of `MatchRules` defined on a `SettingFilter`, then the
// `Setting` matches, which means that we have to follow the configuration defined by
// `Setting.Channels` to decide whether to deliver a notification.
type SettingFilter struct {
	Reason      string             `json:"reason"`
	SubjectType string             `json:"subject_type"`
	Trigger     string             `json:"trigger"`
	MatchRules  []SettingMatchRule `json:"match_rules"`
}

// SettingMatchRule is used to define a way to match Setting attributes in order to define whether a
// setting must apply (or not) to a given event.
//
// For example the `eq` rule allows us to define that a setting will match when the given
// `Attribute` has the specified `Value`
type SettingMatchRule struct {
	ID               int64  `db:"id"`
	RoutingSettingID int64  `db:"routing_setting_id"`
	Attribute        string `db:"attribute"          json:"attribute"`
	Value            string `db:"value"              json:"value"`
	MatchRule        string `db:"match"              json:"match_rule"`
	mysql.Timestamps
}

// RuleEQ returns a new "eq" match rule for routing settings.
func RuleEQ(attr, value string) SettingMatchRule {
	return SettingMatchRule{Attribute: attr, Value: value, MatchRule: "eq"}
}

// CustomField contains the internal data model for custom fields.
type CustomField struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// sqlCustomField contains the SQL data model for custom fields.
type sqlCustomField struct {
	ID               int64  `db:"id"      json:"-"`
	UserID           int64  `db:"user_id" json:"-"`
	RoutingSettingID int64  `db:"meta_id" json:"-"`
	Name             string `db:"name"    json:"name"`
	Value            string `db:"value"   json:"value"`
	mysql.Timestamps
}

// MatchQuery defines the data from the event that will be used in order to decide whether there's a
// matching channel to which we want to deliver a notification or not.
type MatchQuery struct {
	notificationID string
	actorID        int64
	fields         notify.MessageMatchFields
	reasonGroups   []notify.ReasonGroup
}

// Matchable returns nil if and only if the `MatchQuery` is valid and has all the required data in
// order to be matched. It should probably be called `IsValid` instead.
func (n MatchQuery) Matchable() error {
	return n.fields.Matchable()
}

// NewMatchQuery constructs a `MatchQuery` struct.
func NewMatchQuery(notificationID string, actorID int64, fields notify.MessageMatchFields, reasonGroups []notify.ReasonGroup) *MatchQuery {
	return &MatchQuery{
		notificationID: notificationID,
		actorID:        actorID,
		fields:         fields,
		reasonGroups:   reasonGroups,
	}
}
