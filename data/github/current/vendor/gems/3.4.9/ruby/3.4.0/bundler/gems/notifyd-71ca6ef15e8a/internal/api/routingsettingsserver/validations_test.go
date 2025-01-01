package routingsettingsserver

import (
	"context"
	"testing"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/logs"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/routing"

	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	pb "github.com/github/notifyd/proto/services/routingsettings"
)

type ServerValidationsTestSuite struct {
	testsuite.Suite
}

func (suite *ServerValidationsTestSuite) Test_BatchReplace_Validations() {
	ctx := context.Background()

	dummyStorage := routing.NewStorageMock(suite.T())

	service := routing.NewSettingsService(dummyStorage, logs.NullTelem, stats.NullStatter)
	routingSettingsServer := Server{service: service, telem: logs.NullTelem}

	dummyStorage.On("BatchReplace", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Maybe().Return([]int64{}, nil)

	testCases := []struct {
		name                string
		batchReplaceRequest *pb.BatchReplaceRequest
		expectedError       error
	}{
		{
			name: "returns error when user does not exist",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errNoUserID,
		},
		{
			name: "returns error when topics are not present",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						CustomFields: []*pb.CustomField{},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errNoTopic,
		},
		{
			name: "returns error when topics are malformed",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics:       []*pb.Topic{{Type: "repository", Value: "123"}, {Type: "repository"}},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errInvalidTopic,
		},
		{
			name: "returns error when filters are malformed",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*pb.CustomField{},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						Filters: []*pb.Filter{
							{
								Trigger:    "created",
								MatchRules: []*pb.MatchRule{{Attribute: "has_label", Value: "1", MatchRule: "list"}, {Attribute: "title", Value: "sub", MatchRule: "contains"}},
							},
						}},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errInvalidFilter,
		},
		{
			name: "returns error when match rules are malformed",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*pb.CustomField{},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						Filters: []*pb.Filter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules:  []*pb.MatchRule{{Attribute: "has_label", Value: "1"}, {Attribute: "title", Value: "sub", MatchRule: "contains"}},
							},
						},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errInvalidMatchRule,
		},
		{
			name: "returns error when setting custom field name is empty",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						CustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "", Value: "test"}},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errInvalidCustomFieldForSaving,
		},
		{
			name: "returns error when setting custom field value is empty",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						CustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "name", Value: ""}},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{},
			},
			expectedError: errInvalidCustomFieldForSaving,
		},
		{
			name: "returns error when replace by custom fields are missing a name",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels:     []*pb.Channel{{Name: "EMAIL", Enabled: true}},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "", Value: "test"}},
			},
			expectedError: errInvalidCustomFieldForSearching,
		},
		{
			name: "returns error when channels are not provided",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "test", Value: "test"}},
			},
			expectedError: errInvalidNoChannels,
		},
		{
			name: "returns error when channel name is empty",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels:     []*pb.Channel{{Name: " ", Enabled: false}},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "test", Value: "test"}},
			},
			expectedError: errInvalidEmptyChannelName,
		},
		{
			name: "returns error when too many channels provided",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels: []*pb.Channel{
							{Name: "a", Enabled: false},
							{Name: "b", Enabled: false},
							{Name: "c", Enabled: false},
							{Name: "d", Enabled: false},
							{Name: "e", Enabled: false},
							{Name: "f", Enabled: false},
						},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "test", Value: "test"}},
			},
			expectedError: errInvalidTooManyChannels,
		},
		{
			name: "returns error when channel names are duplicated",
			batchReplaceRequest: &pb.BatchReplaceRequest{
				UserId: 1,
				Settings: []*pb.Setting{
					{
						Topics: []*pb.Topic{
							{Type: "repository", Value: "456"},
						},
						Channels: []*pb.Channel{
							{Name: "EMAIL", Enabled: false},
							{Name: "EMAIL", Enabled: true},
						},
						CustomFields: []*pb.CustomField{},
						Filters:      []*pb.Filter{},
					},
				},
				ReplaceByCustomFields: []*pb.CustomField{{Name: "repository_id", Value: "123"}, {Name: "test", Value: "test"}},
			},
			expectedError: errDuplicatedChannels,
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			response, err := routingSettingsServer.BatchReplace(ctx, test.batchReplaceRequest)
			suite.Require().ErrorContains(err, test.expectedError.Error())
			suite.Require().Nil(response)
		})
	}
}

func (suite *ServerValidationsTestSuite) Test_GetRequest_Validations() {
	tests := map[string]struct {
		userIDs       []int64
		fields        []*pb.CustomField
		expectedError error
	}{
		"passed with userID != 0": {
			userIDs:       []int64{1},
			expectedError: nil,
		},
		"passed if no user IDs given": {
			userIDs:       []int64{},
			expectedError: nil,
		},
		"fails to validate if a user IDs is 0": {
			userIDs:       []int64{1, 2, 0, 5},
			expectedError: errors.New("user ID can't be 0 or less"),
		},
	}

	for name, tc := range tests {
		suite.Run(name, func() {
			err := validateGetRequest(tc.userIDs)
			if tc.expectedError == nil {
				suite.Require().Equal(tc.expectedError, err, "validation failed")
			} else {
				suite.Require().Equal(tc.expectedError.Error(), err.Error(), "validation failed")
			}
		})
	}
}

func TestServerValidationsTestSuite(t *testing.T) {
	testsuite.Run(t, new(ServerValidationsTestSuite))
}
