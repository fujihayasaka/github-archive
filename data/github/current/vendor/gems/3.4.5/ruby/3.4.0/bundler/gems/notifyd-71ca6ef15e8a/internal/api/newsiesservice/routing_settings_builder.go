package newsiesservice

import (
	"fmt"
	"strconv"

	matchengine "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"
)

// RoutingSettingsBuilder is an interface for building routing settings.
type RoutingSettingsBuilder interface {
	Title() string
	Filters() []routing.SettingFilter
	CustomFields(fields []routing.CustomField) []routing.CustomField
	Channels() map[string]*matchengine.Channel
	Category() string
	Reason() string
}

type ignoreBuilder struct {
	refType string
	refID   int64
}

// NewIgnoreBuilder creates a new ignore builder.
func NewIgnoreBuilder(refID int64, refType string) RoutingSettingsBuilder {
	return &ignoreBuilder{
		refID:   refID,
		refType: refType,
	}
}

func (b ignoreBuilder) Title() string    { return "Ignore" }
func (b ignoreBuilder) Category() string { return categoryAllValue }
func (b ignoreBuilder) Reason() string   { return "any" }
func (b ignoreBuilder) Channels() map[string]*matchengine.Channel {
	return map[string]*matchengine.Channel{"ALL": {Channel: "ALL", Enabled: false}}
}
func (b ignoreBuilder) Filters() []routing.SettingFilter {
	return []routing.SettingFilter{{
		SubjectType: "any",
		Trigger:     "any",
		MatchRules: []routing.SettingMatchRule{
			routing.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
		},
	}}
}

func (b ignoreBuilder) CustomFields(fields []routing.CustomField) []routing.CustomField {
	return append(fields, []routing.CustomField{
		{Name: CategoryName, Value: b.Category()},
		{Name: WatcherScenarioName, Value: watcherScenarioValue},
		{Name: RepositoryIDName, Value: strconv.FormatInt(b.refID, 10)},
	}...)
}

type ignoreThreadBuilder struct {
	title        string
	reason       string
	repositoryID int64
	threadID     string
	threadType   string
	ownerID      int64
	ownerType    string
}

// NewIgnoreThreadBuilder creates a new ignore thread builder.
func NewIgnoreThreadBuilder(
	title string,
	reason string,
	repositoryID int64,
	threadID string,
	threadType string,
	ownerID int64,
	ownerType string) RoutingSettingsBuilder {
	return ignoreThreadBuilder{
		title:        title,
		reason:       reason,
		repositoryID: repositoryID,
		threadID:     threadID,
		threadType:   threadType,
		ownerID:      ownerID,
		ownerType:    ownerType,
	}
}

func (b ignoreThreadBuilder) Title() string {
	return b.title
}

func (b ignoreThreadBuilder) Filters() []routing.SettingFilter {
	// NOTE: (@dev-tim 2022-10-21) here mute several reasons as we did it for Gists.
	//
	// This logic has to be changed as soon as we have generic approach for muting Gist notifications
	return []routing.SettingFilter{
		{
			Reason:      "author",
			SubjectType: "any",
			Trigger:     "any",
			MatchRules:  []routing.SettingMatchRule{},
		},
		{
			Reason:      "comment",
			SubjectType: "any",
			Trigger:     "any",
			MatchRules:  []routing.SettingMatchRule{},
		},
		{
			Reason:      "manual",
			SubjectType: "any",
			Trigger:     "any",
			MatchRules:  []routing.SettingMatchRule{},
		},
	}
}

func (b ignoreThreadBuilder) CustomFields(_ []routing.CustomField) []routing.CustomField {
	base := []routing.CustomField{
		{Name: CategoryName, Value: b.Category()},

		{Name: ThreadIDName, Value: b.threadID},
		{Name: ThreadTypeName, Value: b.threadType},
		{Name: OwnerIDName, Value: strconv.FormatInt(b.ownerID, 10)},
		{Name: OwnerTypeName, Value: b.ownerType},
	}

	if b.repositoryID > 0 {
		base = append(base, routing.CustomField{
			Name: RepositoryIDName, Value: fmt.Sprintf("%d", b.repositoryID),
		})
	}

	return base
}

func (b ignoreThreadBuilder) Channels() map[string]*matchengine.Channel {
	return map[string]*matchengine.Channel{"ALL": {Channel: "ALL", Enabled: false}}
}

func (b ignoreThreadBuilder) Category() string {
	return CategoryThreadValue
}

func (b ignoreThreadBuilder) Reason() string {
	return ""
}
