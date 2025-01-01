package subscriptions

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Details_Value(t *testing.T) {
	tests := []struct {
		name     string
		details  Details
		expected string
	}{
		{
			name:     "empty details",
			details:  Details{},
			expected: "empty_details",
		},
		{
			name: "full details",
			details: Details{
				Reason: "mention",
				Filters: []Filter{{
					SubjectType: "issue",
					Trigger:     "any",
					MatchRules: []MatchRule{{
						ID:             1,
						SubscriptionID: 1,
						Attribute:      "label_id",
						Value:          "1",
						MatchRule:      "eq",
					}},
				}},
				Topics: []Topic{{Type: "repository", Value: "1"}},
				CustomFields: []CustomField{{
					Name:  "label",
					Value: "wip",
				}},
			},
			expected: "full_details",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			actual, err := test.details.Value()

			expected := readFixture(t, test.expected)
			require.NoError(t, err)
			require.Equal(t, expected, actual)
		})
	}
}

func Test_Details_Scan(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected Details
	}{
		{
			name:     "empty details",
			input:    "empty_details",
			expected: Details{},
		},
		{
			name:  "full details",
			input: "full_details",
			expected: Details{
				Reason: "mention",
				Filters: []Filter{{
					SubjectType: "issue",
					Trigger:     "any",
					MatchRules: []MatchRule{{
						ID:             1,
						SubscriptionID: 1,
						Attribute:      "label_id",
						Value:          "1",
						MatchRule:      "eq",
					}},
				}},
				Topics: []Topic{{Type: "repository", Value: "1"}},
				CustomFields: []CustomField{{
					Name:  "label",
					Value: "wip",
				}},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			value := readFixture(t, test.input)
			detail := &Details{}
			err := detail.Scan(value)

			require.NoError(t, err)
			require.Equal(t, test.expected, *detail)
		})
	}
}

func readFixture(t *testing.T, file string) string {
	fixture, err := os.ReadFile(fmt.Sprintf("testdata/%s.json", file))
	require.NoError(t, err)
	return strings.TrimSuffix(string(fixture), "\n")
}
