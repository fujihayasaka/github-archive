package subscriptionsserver

import (
	"testing"

	testsuite "github.com/stretchr/testify/suite"

	api_pb "github.com/github/notifyd/proto/services/subscriptions"
)

type ServerValidationsTestSuite struct {
	testsuite.Suite
}

func (suite *ServerValidationsTestSuite) TestGet_Validations() {
	testCases := []struct {
		name       string
		getRequest *api_pb.GetRequest
		err        error
	}{
		{
			name: "returns error when user id is wrong",
			getRequest: &api_pb.GetRequest{
				UserId:               -1,
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "label_id", Value: "5"}},
			},
			err: errNoUserID,
		},
		{
			name: "returns error when custom fields are malformed",
			getRequest: &api_pb.GetRequest{
				UserId:               1,
				FilterByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Value: "5"}},
			},
			err: errInvalidCustomFieldForSearching,
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			err := getValidation(test.getRequest)
			suite.Require().ErrorIs(err, test.err)
		})
	}
}

func (suite *ServerValidationsTestSuite) Test_BatchReplace_Validations() {
	testCases := []struct {
		name                string
		batchReplaceRequest *api_pb.BatchReplaceRequest
		expectedError       error
	}{
		{
			name: "returns error when user does not exist",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errNoUserID,
		},
		{
			name: "returns error when reason is not present",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errNoReason,
		},
		{
			name: "returns error when topics are not present",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason:       "subscribed",
						CustomFields: []*api_pb.CustomField{},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errNoTopic,
		},
		{
			name: "returns error when topics are malformed",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason:       "subscribed",
						Topics:       []*api_pb.Topic{{Type: "repository", Value: "123"}, {Type: "repository"}},
						CustomFields: []*api_pb.CustomField{},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errInvalidTopic,
		},
		{
			name: "returns error when filters are malformed",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{},
						Filters: []*api_pb.Filter{
							{
								Trigger:    "created",
								MatchRules: []*api_pb.MatchRule{{Attribute: "has_label", Value: "1", MatchRule: "list"}, {Attribute: "title", Value: "sub", MatchRule: "contains"}},
							},
						}},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errInvalidFilter,
		},
		{
			name: "returns error when match rules are malformed",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{},
						Filters: []*api_pb.Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules:  []*api_pb.MatchRule{{Attribute: "has_label", Value: "1"}, {Attribute: "title", Value: "sub", MatchRule: "contains"}},
							},
						},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errInvalidMatchRule,
		},
		{
			name: "returns error when subscription custom field name is empty",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "", Value: "test"}},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errInvalidCustomFieldForSaving,
		},
		{
			name: "returns error when subscription custom field value is empty",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "name", Value: ""}},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{},
			},
			expectedError: errInvalidCustomFieldForSaving,
		},
		{
			name: "returns error when replace by custom fields are missing a name",
			batchReplaceRequest: &api_pb.BatchReplaceRequest{
				UserId: 1,
				NewSubscriptions: []*api_pb.BatchReplaceCreateRequest{
					{
						Reason: "subscribed",
						Topics: []*api_pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*api_pb.CustomField{},
						Filters:      []*api_pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*api_pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "", Value: "test"}},
			},
			expectedError: errInvalidCustomFieldForSearching,
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			err := batchReplaceValidations(test.batchReplaceRequest)
			suite.Require().ErrorIs(err, test.expectedError)
		})
	}
}

func TestServerValidationsTestSuite(t *testing.T) {
	testsuite.Run(t, new(ServerValidationsTestSuite))
}
