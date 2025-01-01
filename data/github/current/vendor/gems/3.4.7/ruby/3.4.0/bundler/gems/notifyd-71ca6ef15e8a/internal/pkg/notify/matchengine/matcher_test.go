package matchengine

import (
	"sort"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func TestGetRecipientsToReasons(t *testing.T) {
	r := require.New(t)

	testCases := []struct {
		name                   string
		matchedEntries         []*MatchedEntry
		notificationAttributes []notify.Attribute
		recipientIDsToReasons  map[int64][]string
	}{
		{
			name: "matches all pre-filtered recipients",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "1", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "2", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "added_label", Value: "3", MatchRule: "eq"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "has_label", Value: "2"},
				{Name: "added_label", Value: "3"},
			},
			recipientIDsToReasons: map[int64][]string{
				1: {"subscribed"},
				2: {"subscribed"},
			},
		},
		{
			name: "filters out subscriptions if attributes don't match all the rules - 1",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "1", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "2", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "added_label", Value: "3", MatchRule: "eq"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "has_label", Value: "2"},
			},
			recipientIDsToReasons: map[int64][]string{
				1: {"subscribed"},
			},
		},
		{
			name: "filters out subscriptions if attributes don't match all the rules - 2",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "1", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "2", MatchRule: "eq"},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "added_label", Value: "3", MatchRule: "eq"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "added_label", Value: "3"},
			},
			recipientIDsToReasons: map[int64][]string{
				1: {"subscribed"},
			},
		},
		{
			name: "select subscription if match rules doesn't include all the notification attributes",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "subscribed", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 2, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "1", MatchRule: "eq"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "added_label", Value: "3"},
			},
			recipientIDsToReasons: map[int64][]string{
				1: {"subscribed"},
				2: {"subscribed"},
			},
		},
		{
			name: "result contains all matched reasons",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 1, Reason: "mention", Attribute: "", Value: "", MatchRule: ""},
				{UserID: 1, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "1", MatchRule: "eq"},
				{UserID: 1, RefID: 2, Reason: "subscribed", Attribute: "has_label", Value: "2", MatchRule: "eq"},
				{UserID: 1, RefID: 2, Reason: "subscribed", Attribute: "added_label", Value: "3", MatchRule: "eq"},
				{UserID: 1, RefID: 3, Reason: "ci_activity", Attribute: "added_label", Value: "3", MatchRule: "eq"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "has_label", Value: "2"},
				{Name: "added_label", Value: "3"},
			},
			recipientIDsToReasons: map[int64][]string{
				1: {"ci_activity", "mention", "subscribed"},
			},
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			// RecipientReasons is used only for subscriptions now
			matcher := BuildMatcherForSubscriptions(logs.NullTelem, test.notificationAttributes)
			matcher.LoadMatchedEntries(test.matchedEntries)

			recipientIDsToReasons := matcher.RecipientReasons()
			r.Equal(len(test.recipientIDsToReasons), len(recipientIDsToReasons))
			for expectedRecipientID, expectedReasons := range test.recipientIDsToReasons {
				reasons, ok := recipientIDsToReasons[expectedRecipientID]
				sort.Strings(reasons)
				r.True(ok)
				r.Equal(expectedReasons, reasons)
			}
		})
	}
}

func Test_FilterByMatchRules(t *testing.T) {
	r := require.New(t)

	testCases := []struct {
		name                           string
		matchedEntries                 []*MatchedEntry
		notificationAttributes         []notify.Attribute
		notificationRecipientToReasons notify.RecipientIDToReasons
		notificationReasonGroups       []notify.ReasonGroup
		matchResult                    map[int64][]*MatchedEntry
	}{
		{
			name: "matches ignore setting",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
				{UserID: 1, RefID: 2, Attribute: "notify_muted", Value: "1", MatchRule: "ne"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "thread_participant_activity", Value: "true"},
				{Name: "notify_muted", Value: "2"},
			},
			matchResult: map[int64][]*MatchedEntry{
				1: {
					{UserID: 1, RefID: 2, Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
					{UserID: 1, RefID: 2, Attribute: "notify_muted", Value: "1", MatchRule: "ne"},
				},
			},
		},
		{
			name: "does not match ignore setting",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
				{UserID: 1, RefID: 2, Attribute: "notify_muted", Value: "1", MatchRule: "ne"},
			},
			notificationAttributes: []notify.Attribute{
				{Name: "thread_participant_activity", Value: "true"},
				{Name: "notify_muted", Value: "1"},
			},
			matchResult: map[int64][]*MatchedEntry{},
		},
		{
			name: "matches settings with in_reason_group match rule",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Value: "participant", MatchRule: "in_reason_group"},
			},
			notificationRecipientToReasons: map[int64][]string{
				1: {"mention"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "subscribed"},
				},
			},
			matchResult: map[int64][]*MatchedEntry{
				1: {
					{UserID: 1, RefID: 2, Value: "participant", MatchRule: "in_reason_group"},
				},
			},
		},
		{
			name: "matches settings with not_in_reason_group match rule",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Value: "participant", MatchRule: "not_in_reason_group"},
			},
			notificationRecipientToReasons: map[int64][]string{
				1: {"request_review"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "subscribed"},
				},
			},
			matchResult: map[int64][]*MatchedEntry{
				1: {
					{UserID: 1, RefID: 2, Value: "participant", MatchRule: "not_in_reason_group"},
				},
			},
		},
		{
			name: "doesn't match settings because of in_reason_group match rule",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Value: "participant", MatchRule: "in_reason_group"},
			},
			notificationRecipientToReasons: map[int64][]string{
				1: {"request_review"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "subscribed"},
				},
			},
			matchResult: map[int64][]*MatchedEntry{},
		},
		{
			name: "doesn't match settings because of not_in_reason_group match rule",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Value: "participant", MatchRule: "not_in_reason_group"},
			},
			notificationRecipientToReasons: map[int64][]string{
				1: {"mention"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "subscribed"},
				},
			},
			matchResult: map[int64][]*MatchedEntry{},
		},
		{
			// https://github.com/github/notifyd/discussions/3239
			name: "not_in_reason_group doesn't return early",
			matchedEntries: []*MatchedEntry{
				{UserID: 1, RefID: 2, Value: "true", Attribute: "watch_activity", MatchRule: "eq"},
				{UserID: 1, RefID: 2, Value: "participant", MatchRule: "not_in_reason_group"},
			},
			notificationRecipientToReasons: map[int64][]string{
				1: {"subscribed"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention"},
				},
			},
			matchResult: map[int64][]*MatchedEntry{},
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			matcher := BuildMatcherForRoutingSettings(nil, test.notificationAttributes, test.notificationRecipientToReasons, test.notificationReasonGroups)
			matcher.LoadMatchedEntries(test.matchedEntries)
			r.Equal(test.matchResult, matcher.MatchedRecipients())
		})
	}
}

func Test_checkNotEqualityMatchRule(t *testing.T) {
	r := require.New(t)

	tests := map[string]struct {
		notificationAttributes []notify.Attribute
		rule                   GroupedMatchRule
		expectedMatch          bool
	}{
		"simple non-equality match": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "2"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1"},
			}},
			expectedMatch: true,
		},
		"simple non-equality mismatch": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1"},
			}},
			expectedMatch: false,
		},
		"empty match attributes": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "2"},
			},
			rule:          GroupedMatchRule{"ne": GroupedAttributes{}},
			expectedMatch: true,
		},
		"notification attributes are nil": {
			notificationAttributes: nil,
			rule:                   GroupedMatchRule{"ne": GroupedAttributes{}},
			expectedMatch:          true,
		},
		"one out of many non-equality mismatch": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "1"},
				{Name: "has_label", Value: "2"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1"},
			}},
			expectedMatch: false,
		},
		"one out of many non-equality match": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "2"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1"},
			}},
			expectedMatch: true,
		},
		"many out of many non-equality match": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "4"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1", "2"},
			}},
			expectedMatch: true,
		},
		"many out of many non-equality mismatch": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "2"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1", "2"},
			}},
			expectedMatch: false,
		},
		"many out of many non-equality match with unrelated attributes": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "4"},
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1", "2"},
			}},
			expectedMatch: true,
		},
		"many out of many non-equality mismatch with unrelated attributes": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "2"},
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label": []string{"1", "2"},
			}},
			expectedMatch: false,
		},
		"many out of many non-equality mismatch with many attributes": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "2"},
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label":   []string{"1", "2"},
				"added_label": []string{"3"},
			}},
			expectedMatch: false,
		},
		"many out of many non-equality match with many attributes": {
			notificationAttributes: []notify.Attribute{
				{Name: "has_label", Value: "3"},
				{Name: "has_label", Value: "4"},
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{"ne": GroupedAttributes{
				"has_label":   []string{"1", "2"},
				"added_label": []string{"5"},
			}},
			expectedMatch: true,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ret := newMatcher(logs.NullTelem, tc.notificationAttributes, notify.RecipientIDToReasons{}, []notify.ReasonGroup{}).ruleMatches(tc.rule, 0)
			r.Equal(tc.expectedMatch, ret)
		})
	}
}

func Test_InReasonGroupMatchRule(t *testing.T) {
	r := require.New(t)

	tests := map[string]struct {
		recipientID                      int64
		notificationAttributes           []notify.Attribute
		notificationReasonGroups         []notify.ReasonGroup
		notificationRecipientIDToReasons notify.RecipientIDToReasons
		rule                             GroupedMatchRule
		expectedMatch                    bool
	}{
		"matches when recipient reason is in reason group": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},

			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"author", "review_requested"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: true,
		},
		"doesn't match when recipient reason is not in a reason group": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"mention", "ci_activity"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: false,
		},
		"doesn't when match rule has unknown reason group": {
			recipientID:            1,
			notificationAttributes: []notify.Attribute{},
			rule: GroupedMatchRule{
				"in_reason_group": GroupedAttributes{
					"": []string{"unknown_reason_group"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"mention", "ci_activity"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "commented"},
				},
			},
			expectedMatch: false,
		},
		"matches when in_reason_group and eq and ne rules are present": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"ne": GroupedAttributes{
					"added_label": []string{"4"},
				},
				"in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"author", "review_requested"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: true,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ret := BuildMatcherForRoutingSettings(logs.NullTelem, tc.notificationAttributes, tc.notificationRecipientIDToReasons, tc.notificationReasonGroups).ruleMatches(tc.rule, tc.recipientID)
			r.Equal(tc.expectedMatch, ret)
		})
	}
}

func Test_NotInReasonGroupMatchRule(t *testing.T) {
	r := require.New(t)

	tests := map[string]struct {
		recipientID                      int64
		notificationAttributes           []notify.Attribute
		notificationReasonGroups         []notify.ReasonGroup
		notificationRecipientIDToReasons notify.RecipientIDToReasons
		rule                             GroupedMatchRule
		expectedMatch                    bool
	}{
		"matches when recipient reason is NOT in reason group": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},

			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"not_in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"reviewer", "review_requested"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: true,
		},
		"doesn't match when recipient reason is in a reason group": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"not_in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"mention", "ci_activity"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: true,
		},
		"matches when match rule has unknown reason group and we use not_in_reason_group": {
			recipientID:            1,
			notificationAttributes: []notify.Attribute{},
			rule: GroupedMatchRule{
				"not_in_reason_group": GroupedAttributes{
					"": []string{"unknown_reason_group"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"mention", "ci_activity"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"mention", "commented"},
				},
			},
			expectedMatch: true,
		},
		"matches when not_in_reason_group and eq and ne rules are present": {
			recipientID: 1,
			notificationAttributes: []notify.Attribute{
				{Name: "added_label", Value: "3"},
			},
			rule: GroupedMatchRule{
				"eq": GroupedAttributes{
					"added_label": []string{"3"},
				},
				"ne": GroupedAttributes{
					"added_label": []string{"4"},
				},
				"not_in_reason_group": GroupedAttributes{
					"": []string{"participant"},
				},
			},
			notificationRecipientIDToReasons: map[int64][]string{
				1: {"mentioned", "review_requested"},
			},
			notificationReasonGroups: []notify.ReasonGroup{
				{
					Name:    "participant",
					Reasons: []string{"author", "commented"},
				},
			},
			expectedMatch: true,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ret := BuildMatcherForRoutingSettings(logs.NullTelem, tc.notificationAttributes, tc.notificationRecipientIDToReasons, tc.notificationReasonGroups).ruleMatches(tc.rule, tc.recipientID)
			r.Equalf(tc.expectedMatch, ret, "expected match: %v, got: %v", tc.expectedMatch, ret)
		})
	}
}
