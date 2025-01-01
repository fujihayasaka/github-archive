package newsiesservice

import (
	"errors"
	"fmt"
	"strconv"

	"github.com/github/notifyd/internal/pkg/subscriptions"
)

// subscriptionBuilder interface describes what an implementor that wants to be able to build a
// MetaSubscription needs to conform to in order to get each one of the relevant parts sorted out.
type subscriptionBuilder interface {
	Title() string
	Filters() ([]subscriptions.Filter, error)
	CustomFields([]subscriptions.CustomField) ([]subscriptions.CustomField, error)
	Category() string
	Reason() string
}

type listBuilder struct {
	refType string
	refID   int64
}

func (b listBuilder) Title() string    { return "List subscription" }
func (b listBuilder) Category() string { return categoryAllValue }
func (b listBuilder) Reason() string   { return ListReason }
func (b listBuilder) Filters() ([]subscriptions.Filter, error) {
	return []subscriptions.Filter{
		{
			SubjectType: "any",
			Trigger:     "any",
			MatchRules: []subscriptions.MatchRule{
				subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
			},
		},
	}, nil
}

func (b listBuilder) CustomFields(fields []subscriptions.CustomField) ([]subscriptions.CustomField, error) {
	return append([]subscriptions.CustomField{
		{Name: CategoryName, Value: b.Category()},
		{Name: WatcherScenarioName, Value: watcherScenarioValue},
		{Name: RepositoryIDName, Value: strconv.FormatInt(b.refID, 10)},
	}, fields...), nil
}

// ThreadTypeBuilder represents a subscription builder for a thread type.
type ThreadTypeBuilder struct {
	refType string
	refID   int64
	types   []ThreadType
}

// Title returns the title of the subscription.
func (b ThreadTypeBuilder) Title() string { return "Thread Type subscription" }

// Category returns the category of the subscription.
func (b ThreadTypeBuilder) Category() string { return CategoryThreadTypeValue }

// Reason returns the reason of the subscription.
func (b ThreadTypeBuilder) Reason() string { return ThreadTypeReason }

// CustomFields returns the custom fields of the subscription.
func (b ThreadTypeBuilder) CustomFields(fields []subscriptions.CustomField) ([]subscriptions.CustomField, error) {
	targetFields := append([]subscriptions.CustomField{
		{Name: CategoryName, Value: b.Category()},
		{Name: WatcherScenarioName, Value: watcherScenarioValue},
		{Name: RepositoryIDName, Value: strconv.FormatInt(b.refID, 10)},
	}, fields...)

	// NOTE: (@dev-tim 2022-10-07) here we will have problem when we start handling subscriptions
	// with several thread types.
	//
	// The issue is that Custom fields don't work well with non-unique custom fields
	// in cases where we just query by field name, query by value will still work OK.
	for _, t := range b.types {
		switch t {
		case Issue:
			targetFields = append(targetFields, subscriptions.CustomField{Name: ThreadTypeName, Value: "issue"})
		case PullRequest:
			targetFields = append(targetFields, subscriptions.CustomField{Name: ThreadTypeName, Value: "pull_request"})
		case Release:
			targetFields = append(targetFields, subscriptions.CustomField{Name: ThreadTypeName, Value: "release"})
		case Discussion:
			targetFields = append(targetFields, subscriptions.CustomField{Name: ThreadTypeName, Value: "discussion"})
		case SecurityAlert:
			targetFields = append(targetFields, subscriptions.CustomField{Name: ThreadTypeName, Value: "security_alert"})
		default:
			return nil, errNotImplemented
		}
	}

	return targetFields, nil
}

// NOTE: (@franciscoj 2022-09-21) errNotImplemented is a temporary utility in order to make it
// explicit some of the thread types did not have an explicit implementation (yet). Once they are
// all implemented we should remove it.
var errNotImplemented = errors.New("not implemented")

// errUnknownType appears whenever we try to generate Filters for an unknown type.
var errUnknownType = errors.New("unknown thread type")

// Filters returns the filters of the subscription.
func (b ThreadTypeBuilder) Filters() ([]subscriptions.Filter, error) {
	var filters []subscriptions.Filter

	for _, t := range b.types {
		switch t {
		case Issue:
			filters = b.appleThreadTypeFilter(filters, "issue")
		case PullRequest:
			filters = b.appleThreadTypeFilter(filters, "pull_request")
		case Release:
			filters = b.appleThreadTypeFilter(filters, "release")
		case Discussion:
			filters = b.appleThreadTypeFilter(filters, "discussion")
		case SecurityAlert:
			filters = b.appleThreadTypeFilter(filters, "security_alert")
		default:
			return nil, errUnknownType
		}
	}

	return filters, nil
}

func (b ThreadTypeBuilder) appleThreadTypeFilter(filters []subscriptions.Filter, threadType string) []subscriptions.Filter {
	filters = append(filters, subscriptions.Filter{
		SubjectType: "any",
		Trigger:     "any",
		MatchRules: []subscriptions.MatchRule{
			subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
			subscriptions.RuleEQ(ThreadTypeMatchRuleName, threadType),
		},
	})
	return filters
}

// ThreadBuilder represents a subscription builder for a thread.
type ThreadBuilder struct {
	title        string
	reason       string
	repositoryID int64
	threadID     string
	threadType   string
	ownerID      int64
	ownerType    string
}

// NewThreadBuilder creates a new ThreadBuilder.
func NewThreadBuilder(title string,
	reason string,
	repositoryID int64,
	threadID string,
	threadType string,
	ownerID int64,
	ownerType string) subscriptionBuilder {
	return &ThreadBuilder{
		title:        title,
		reason:       reason,
		repositoryID: repositoryID,
		threadType:   threadType,
		threadID:     threadID,
		ownerID:      ownerID,
		ownerType:    ownerType,
	}
}

// Title returns the title of the subscription.
func (t ThreadBuilder) Title() string {
	return t.title
}

// Filters returns the filters of the subscription.
func (t ThreadBuilder) Filters() ([]subscriptions.Filter, error) {
	return []subscriptions.Filter{
		{
			SubjectType: "any",
			Trigger:     "any",
			MatchRules: []subscriptions.MatchRule{
				subscriptions.RuleEQ(ThreadParticipantActivityName, ThreadParticipantActivityValue),
			},
		},
	}, nil
}

// CustomFields returns the custom fields of the subscription.
func (t ThreadBuilder) CustomFields(_ []subscriptions.CustomField) ([]subscriptions.CustomField, error) {
	base := []subscriptions.CustomField{
		{Name: CategoryName, Value: t.Category()},
		{Name: ThreadIDName, Value: t.threadID},
		{Name: ThreadTypeName, Value: t.threadType},
		{Name: OwnerIDName, Value: fmt.Sprintf("%d", t.ownerID)},
		{Name: OwnerTypeName, Value: t.ownerType},
	}

	if t.repositoryID > 0 {
		base = append(base, subscriptions.CustomField{Name: RepositoryIDName, Value: fmt.Sprintf("%d", t.repositoryID)})
	}

	return base, nil
}

// Category returns the category of the subscription.
func (t ThreadBuilder) Category() string { return CategoryThreadValue }

// Reason returns the reason of the subscription.
func (t ThreadBuilder) Reason() string {
	if t.reason == "" {
		return "any"
	}

	return t.reason
}
