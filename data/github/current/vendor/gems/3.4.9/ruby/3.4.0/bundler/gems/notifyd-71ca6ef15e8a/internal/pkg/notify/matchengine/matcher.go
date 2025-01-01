// Package matchengine implements the logic for matching recipients and reasons.
package matchengine

import (
	"slices"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
)

// ErrReasonGroupNotFound is an error that is returned when an invalid reason group is found.
var ErrReasonGroupNotFound = errors.New("Invalid reason group found")

// Matcher is a struct that holds all the data needed for matching recipients and reasons.
//
// Subscriptions matcher performs the final step of filtering subscriptions that match the data from notification message.
// It creates a list of recipients who intend to receive the notification.
//
// It matches on attributes, but also reason groups.
// Matcher knows 3 methods:
// 1. LoadMatchedEntries - loads matched entries from database
// 2. RecipientReasons - returns a map of recipients and reasons why they match
// 3. MatchedRecipients - returns a list of matched entries per recipient
type Matcher struct {
	telem *telemetry.Provider

	notificationAttributes          map[string]StringSet
	refIDsToGroupedMatchRules       map[int64]GroupedMatchRule
	refIDsToRecipients              map[int64]int64
	refIDToMatchEntries             map[int64][]*MatchedEntry
	resultRecipientIDToMatchEntries map[int64][]*MatchedEntry

	notificationReasonGroups         []notify.ReasonGroup
	notificationRecipientIDToReasons notify.RecipientIDToReasons
}

// BuildMatcherForRoutingSettings creates a new matcher for routing settings.
func BuildMatcherForRoutingSettings(
	telem *telemetry.Provider,
	notificationAttributes []notify.Attribute,
	userReasons notify.RecipientIDToReasons,
	reasonGroups []notify.ReasonGroup,
) *Matcher {
	return newMatcher(telem, notificationAttributes, userReasons, reasonGroups)
}

// BuildMatcherForSubscriptions creates a new matcher for subscriptions.
func BuildMatcherForSubscriptions(
	telem *telemetry.Provider,
	notificationAttributes []notify.Attribute,
) *Matcher {
	return newMatcher(telem, notificationAttributes, nil, nil)
}

func newMatcher(
	telem *telemetry.Provider,
	notificationAttributes []notify.Attribute,
	userReasons notify.RecipientIDToReasons,
	reasonGroups []notify.ReasonGroup,
) *Matcher {
	return &Matcher{
		telem: telem,

		notificationAttributes:           attributesToStringSet(notificationAttributes),
		notificationRecipientIDToReasons: userReasons,
		notificationReasonGroups:         reasonGroups,

		refIDsToGroupedMatchRules: map[int64]GroupedMatchRule{},
		refIDsToRecipients:        map[int64]int64{},

		refIDToMatchEntries:             map[int64][]*MatchedEntry{},
		resultRecipientIDToMatchEntries: map[int64][]*MatchedEntry{},
	}
}

/*
LoadMatchedEntries loads entries pre-selected from database to matcher and transforms them
to the structures more suitable for further matching.

For example, it maps matched entry ref ids to match rules for attributes.

The following matched entries:

RoutingSettingId: 1, Attribute: "has_label", Value: "1", MatchRule: "eq"
RoutingSettingId: 1, Attribute: "has_label", Value: "2", MatchRule: "eq"
RoutingSettingId: 1, Attribute: "title", Value: "subscription", MatchRule: "contains"

Will be converted to the following structure:

		1 => {
			"eq" => {
				"has_label" => ["1", "2"]
			},
			"contains" => {
				"title" => ["subscription"]
			},
	    "in_reason_group" => {
				"" => ["participant"],
			}
		}
*/
func (m *Matcher) LoadMatchedEntries(matchedEntries []*MatchedEntry) {
	for _, entry := range matchedEntries {
		// ref entity has no matching rules for attributes, adding recipient to the result
		if entry.IsEmpty() {
			if _, ok := m.resultRecipientIDToMatchEntries[entry.UserID]; !ok {
				m.resultRecipientIDToMatchEntries[entry.UserID] = []*MatchedEntry{}
			}
			m.resultRecipientIDToMatchEntries[entry.UserID] = append(m.resultRecipientIDToMatchEntries[entry.UserID], entry)
		} else {
			m.addMatchedEntry(entry)
		}

		if _, ok := m.refIDToMatchEntries[entry.RefID]; !ok {
			m.refIDToMatchEntries[entry.RefID] = []*MatchedEntry{}
		}

		m.refIDToMatchEntries[entry.RefID] = append(m.refIDToMatchEntries[entry.RefID], entry)
	}
}

// MatchedRecipients returns a list of matched entries per recipient.
func (m *Matcher) MatchedRecipients() map[int64][]*MatchedEntry {
	m.filterByMatchRules()

	return m.resultRecipientIDToMatchEntries
}

// RecipientReasons returns a map of recipient IDs to reasons.
func (m *Matcher) RecipientReasons() notify.RecipientIDToReasons {
	m.filterByMatchRules()

	// store in a stringset to avoid duplicates
	resultReasons := map[int64]StringSet{}
	for recipientID, matchedRules := range m.resultRecipientIDToMatchEntries {
		for _, rule := range matchedRules {
			if _, ok := resultReasons[recipientID]; !ok {
				resultReasons[recipientID] = StringSet{}
			}
			resultReasons[recipientID][rule.Reason] = true
		}
	}

	// return primitive types
	var resultReasonsMap = make(notify.RecipientIDToReasons)
	for recipientID, reasonStringSet := range resultReasons {
		for reason := range reasonStringSet {
			resultReasonsMap[recipientID] = append(resultReasonsMap[recipientID], reason)
		}
	}

	return resultReasonsMap
}

// Add the data from single matched entry to lookup structures for faster matching
func (m *Matcher) addMatchedEntry(entry *MatchedEntry) {
	m.addMatchRule(entry.RefID, string(entry.Attribute), string(entry.Value), string(entry.MatchRule))

	// add mappings
	m.refIDsToRecipients[entry.RefID] = entry.UserID
}

func (m *Matcher) addMatchRule(refID int64, attributeName, attributeValue, matchRule string) {
	// in case we have attributes to match, add them to a separate structure in order to match them on the next step
	rule, ok := m.refIDsToGroupedMatchRules[refID]
	if !ok {
		rule = GroupedMatchRule{}
	}
	rule.addMatchRule(attributeName, attributeValue, matchRule)
	m.refIDsToGroupedMatchRules[refID] = rule
}

// filterByMatchRules goes through match rules and check that match rules stored for subscription match the attributes on notification message.
func (m *Matcher) filterByMatchRules() {
	for refID, groupedMatchRule := range m.refIDsToGroupedMatchRules {
		recipientID := m.refIDsToRecipients[refID]
		matchEntries := m.refIDToMatchEntries[refID]

		if m.ruleMatches(groupedMatchRule, recipientID) {
			if _, ok := m.resultRecipientIDToMatchEntries[recipientID]; !ok {
				m.resultRecipientIDToMatchEntries[recipientID] = matchEntries
			} else {
				m.resultRecipientIDToMatchEntries[recipientID] = append(m.resultRecipientIDToMatchEntries[recipientID], matchEntries...)
			}
		}
	}
}

// ruleMatches returns true if all the attributes in the rule are matched, false otherwise.
// Currently only "eq" and "ne" rules are supported, and an unsupported rule never checks.
// For supported rules, all the rule attributes are checked against the set of notification attributes.
// Depending on the match rule, either all ("eq") or none ("ne") of the rule attributes must be present in notification attributes.
//
// In set terminology, if N is the set of notification attributes and R is the set of rule attributes:
// - "eq" rule = N ∩ R = R
// - "ne" rule = N ∩ R = ϕ
//
// For example:
// grouped attributes on match rule contains: "has_label" => [1,2,3]
// this means that in order to match rule "eq" notification attributes must contain
// "has_label" => [1,2,3] or
// "has_label" => [1,2,3,4]
// But if notification attributes contain "has_label" => [1,2] the rule will not match.
//
// Similarly, in order to match rule "ne" notification attributes must not contain any of [1,2,3] label_ids.
// These will match:
// "has_label" => [4,5] or
// "has_label" => []
// But if attributes contain something "has_label" => [1] the rule will not match.
func (m *Matcher) ruleMatches(groupedMatchRule GroupedMatchRule, recipientID int64) bool {
	for rule, attributes := range groupedMatchRule {
		for name, values := range attributes {
			for _, value := range values {
				result := false
				switch rule {
				case "eq":
					result = m.eq(name, value)
				case "ne":
					result = m.ne(name, value)
				case "in_reason_group":
					result = m.inReasonGroup(recipientID, value)
				case "not_in_reason_group":
					result = m.notInReasonGroup(recipientID, value)
				}
				if !result {
					return false
				}
			}
		}
	}
	return true
}

func (m *Matcher) eq(name, value string) bool {
	_, found := m.notificationAttributes[name][value]
	return found
}

func (m *Matcher) ne(name, value string) bool {
	return !m.eq(name, value)
}

func (m *Matcher) inReasonGroup(userID int64, value string) bool {
	// Find the rule reason group in the notification event
	var group notify.ReasonGroup
	found := false
	for _, g := range m.notificationReasonGroups {
		if g.Name == value {
			group = g
			found = true
			break
		}
	}

	// TODO(abeaumont): Error handling shouldn't happen in the inner loop.
	// A better approach may be to accumulate the errors and report them once out of the loop.
	if !found {
		m.telem.Logger.
			WithError(ErrReasonGroupNotFound).
			WithFields(kvp.String("gh.notifyd.reason_group", value)).
			Error("Reason group not found in notification event")
		return false
	}

	// Get the user reasons
	reasons, found := m.notificationRecipientIDToReasons[userID]
	if !found || len(reasons) == 0 {
		return false
	}

	// Any of the user reasons are in the reason group?
	for _, reason := range reasons {
		if slices.Contains(group.Reasons, reason) {
			return true
		}
	}
	return false
}

func (m *Matcher) notInReasonGroup(userID int64, value string) bool {
	return !m.inReasonGroup(userID, value)
}
