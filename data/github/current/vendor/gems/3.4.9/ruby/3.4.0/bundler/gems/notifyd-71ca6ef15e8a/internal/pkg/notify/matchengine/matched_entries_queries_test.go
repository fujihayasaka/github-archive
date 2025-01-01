package matchengine

import (
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/notify"
)

func Test_matchedEngriesQueries_findByFields(t *testing.T) {
	r := require.New(t)

	tests := map[string]struct {
		expectedQuery      string
		expectedParameters []interface{}
		matchFields        notify.MessageMatchFields
	}{
		"get subscriptions without attributes": {
			matchFields: notify.MessageMatchFields{
				Topics: []notify.Topic{{
					Type:  "repository",
					Value: "123",
				}},
				SubjectType: "issue",
				Trigger:     "labeled",
			},
			expectedQuery: buildExpectedQuery(t, "(subscription_match_rules.subscription_id IS NULL)"),
			expectedParameters: []interface{}{
				"repository", "123", "any", "any", "issue", "any", "issue",
				"labeled",
			},
		},
		"get subscriptions with one attribute": {
			matchFields: notify.MessageMatchFields{
				Topics: []notify.Topic{{
					Type:  "repository",
					Value: "123",
				}},
				SubjectType: "issue",
				Trigger:     "labeled",
				Attributes: []notify.Attribute{
					{Name: "author_id", Value: "123"},
				},
			},
			expectedQuery: buildExpectedQuery(t, "(subscription_match_rules.subscription_id IS NULL OR (subscription_match_rules.attribute = ? AND (subscription_match_rules.value = ? OR subscription_match_rules.match <> ?)))"),
			expectedParameters: []interface{}{
				"repository", "123", "any", "any", "issue", "any", "issue",
				"labeled", "author_id", "123", "eq",
			},
		},
		"get subscriptions with multiple attributes": {
			matchFields: notify.MessageMatchFields{
				Topics: []notify.Topic{{
					Type:  "repository",
					Value: "123",
				}},
				SubjectType: "issue",
				Trigger:     "labeled",
				Attributes: []notify.Attribute{
					{Name: "author_id", Value: "123"},
					{Name: "added_label", Value: "456"},
				},
			},
			expectedQuery: buildExpectedQuery(t, "(subscription_match_rules.subscription_id IS NULL OR (subscription_match_rules.attribute = ? AND (subscription_match_rules.value = ? OR subscription_match_rules.match <> ?)) OR (subscription_match_rules.attribute = ? AND (subscription_match_rules.value = ? OR subscription_match_rules.match <> ?)))"),
			expectedParameters: []interface{}{
				"repository", "123", "any", "any", "issue", "any", "issue",
				"labeled", "author_id", "123", "eq", "added_label", "456", "eq",
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			queries := matchedEntriesQueries{}
			rawQuery, params, err := queries.findByFields(test.matchFields).ToSql()
			r.NoError(err)

			expected, actual := prepareQueries(t, test.expectedQuery, rawQuery)

			r.Equal(expected, actual)
			r.Equal(test.expectedParameters, params)
		})
	}
}

// prepareQueries performs some cleanup on the queries for comparation (remove white space, etc)
func prepareQueries(t *testing.T, expected, actual string) (expectedQuery, actualQuery string) {
	t.Helper()

	space := regexp.MustCompile(`\s+`)

	expectedQuery = strings.ReplaceAll(expected, "\r\n", " ")
	expectedQuery = strings.ReplaceAll(expectedQuery, "\n", " ")
	expectedQuery = space.ReplaceAllString(expectedQuery, " ")

	actualQuery = strings.ReplaceAll(actual, "\n", " ")
	actualQuery = space.ReplaceAllString(actualQuery, " ")

	return expectedQuery, actualQuery
}

func buildExpectedQuery(t *testing.T, dynamicPart string) string {
	t.Helper()

	return strings.ReplaceAll(`SELECT
		 pre_selected_subscriptions.id AS ref_id,
		 pre_selected_subscriptions.user_id,
		 pre_selected_subscriptions.reason,
		 subscription_match_rules.attribute,
		 subscription_match_rules.value, `+
		"subscription_match_rules.`match` AS match_rule FROM "+
		"(SELECT subscriptions_v2.id, user_id, reason FROM subscriptions_v2 "+
		" 		LEFT JOIN subscription_match_rules ON subscriptions_v2.id = `subscription_match_rules`.subscription_id "+
		` 		WHERE ((subscriptions_v2.topic_type = ? AND subscriptions_v2.topic_value = ?)) AND
		 		((subscriptions_v2.subject_type = ? AND subscriptions_v2.trigger = ?) OR
					(subscriptions_v2.subject_type = ? AND subscriptions_v2.trigger = ?) OR
					(subscriptions_v2.subject_type = ? AND subscriptions_v2.trigger = ?)) AND `+
		dynamicPart+") AS pre_selected_subscriptions LEFT JOIN subscription_match_rules ON pre_selected_subscriptions.id = `subscription_match_rules`.subscription_id",
		"\n", "")
}
