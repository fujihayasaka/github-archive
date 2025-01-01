package subscriptionsserver

import (
	"testing"

	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/subscriptions"
	api_pb "github.com/github/notifyd/proto/services/subscriptions"
)

type ConvertersTestSuite struct {
	testsuite.Suite
}

func (suite *ConvertersTestSuite) TestPbToCustomFields() {
	testCase := []struct {
		name     string
		input    []*api_pb.CustomField
		expected []*subscriptions.CustomField
	}{
		{
			name:     "no data",
			input:    []*api_pb.CustomField{},
			expected: []*subscriptions.CustomField{},
		},
		{
			name: "both name and value present",
			input: []*api_pb.CustomField{
				{Name: "1", Value: "1"},
				{Name: "2", Value: "2"},
			},
			expected: []*subscriptions.CustomField{
				{Name: "1", Value: "1"},
				{Name: "2", Value: "2"},
			},
		},
	}

	for _, test := range testCase {
		suite.Run(test.name, func() {
			actual := pbToCustomFields(test.input)
			suite.Require().Len(actual, len(test.expected))

			for idx, field := range test.expected {
				suite.Require().Equal(field.Name, actual[idx].Name)
				suite.Require().Equal(field.Value, actual[idx].Value)
			}
		})
	}
}

func (suite *ConvertersTestSuite) TestPbNewSubscriptionsToMetaSubscriptions() {
	testCase := []struct {
		name     string
		input    []*api_pb.BatchReplaceCreateRequest
		expected []*subscriptions.MetaSubscription
	}{
		{
			name:     "no data",
			input:    []*api_pb.BatchReplaceCreateRequest{},
			expected: []*subscriptions.MetaSubscription{},
		},
		{
			name: "all fields filled in",
			input: []*api_pb.BatchReplaceCreateRequest{
				{
					Reason: "subscribed",
					Topics: []*api_pb.Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					Filters: []*api_pb.Filter{
						{
							SubjectType: "issue",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
						{
							SubjectType: "pull_request",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
					},
					CustomFields: []*api_pb.CustomField{
						{Name: "repository_id", Value: "123"},
						{Name: "label_id", Value: "1"},
					},
				},
			},
			expected: []*subscriptions.MetaSubscription{
				{
					UserID: 1,
					Details: subscriptions.Details{
						Reason: "subscribed",
						Topics: []subscriptions.Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						CustomFields: []subscriptions.CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
						Filters: []subscriptions.Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []subscriptions.MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []subscriptions.MatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
					},
				},
			},
		},
	}
	var userID int64 = 1

	for _, test := range testCase {
		suite.Run(test.name, func() {
			actual := pbNewSubscriptionsToMetaSubscriptions(userID, test.input)
			suite.Require().Len(actual, len(test.expected))
			for idx, expectedSubscription := range test.expected {
				subscriptions.AssertMetaSubscriptionsEqual(suite.T(), expectedSubscription, actual[idx])
			}
		})
	}
}

func TestConvertersTestSuite(t *testing.T) {
	testsuite.Run(t, new(ConvertersTestSuite))
}
