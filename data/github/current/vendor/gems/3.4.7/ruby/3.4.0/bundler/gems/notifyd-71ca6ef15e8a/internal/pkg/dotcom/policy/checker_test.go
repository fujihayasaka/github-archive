package policy

import (
	"context"
	"sort"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/structpb"
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

	email "github.com/github/notifyd/internal/email/datastructures"
	api_client "github.com/github/notifyd/internal/pkg/dotcom"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	notifyd "github.com/github/notifyd/proto/notifyd/v1"
)

func TestCanDeliverPushNotification(t *testing.T) {
	r := require.New(t)
	notifydAPIMock := api_client.NewNotifydAPIMock(t)

	checker := checker{telem: logs.NullTelem, notifydAPIClient: notifydAPIMock}
	ctx := context.Background()
	req := notifyd.CheckDeliverMobilePushPolicyRequest{
		UserId:              int32(123),
		SkipSamlEnforcement: false,
		OrganizationId:      int32(987),
		OauthAccessId:       int64(567),
		Reasons:             []string{"mention", "assign"},
	}
	resp := notifyd.CheckDeliverMobilePushPolicyResponse{
		IsDeliverable: true,
		Error:         "",
	}
	// Protobufs can't be compared with reflect.DeepEqual() which mock uses by default,
	// so we use a custom matcher function using proto.Equal()
	// see https://github.com/osrg/gobgp/issues/1952
	reqMatchFunc := func(actualReq *notifyd.CheckDeliverMobilePushPolicyRequest) bool {
		return proto.Equal(actualReq, &req)
	}
	tenant := tenancy.NewSingleTenant()
	notifydAPIMock.On("CheckDeliverMobilePushPolicy", ctx, tenant, mock.MatchedBy(reqMatchFunc)).Return(&resp, nil)

	result, err := checker.CanDeliverPushNotification(ctx, tenant, int64(req.UserId), req.SkipSamlEnforcement, int64(req.OrganizationId), req.OauthAccessId, req.Reasons)
	r.NoError(err)
	r.True(result.IsDeliverable)
	r.Equal("", result.NotDeliverableReason)
}

func Test_GetDeliverEmailData(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()

	matchData, err := structpb.NewStruct(map[string]interface{}{
		"subject_type": "Gist",
		"attributes": []interface{}{
			map[string]interface{}{"name": "thread_id", "value": "123"},
		},
	})
	notificationID, _ := structpb.NewStruct(map[string]interface{}{
		"notification_id": "",
	})

	r.NoError(err)

	req := notifyd.GetDeliverEmailDataRequest{
		UserId:         1,
		OrganizationId: 1,
		AuthTokenRequests: []*notifyd.AuthTokenRequest{
			{Scope: email.MuteAuthScope, Data: matchData},
			{Scope: email.MuteListScope, Data: matchData},
			{Scope: email.EmailReplyScope, Data: notificationID},
		},
	}

	tests := []struct {
		name string
		res  *notifyd.GetDeliverEmailDataResponse
		err  error
	}{
		{
			name: "when the request is correct and not deliverable",
			res: &notifyd.GetDeliverEmailDataResponse{
				IsDeliverable: false,
				Error:         "user not found",
			},
			err: nil,
		},
		{
			name: "when the request is correct and deliverable",
			res: &notifyd.GetDeliverEmailDataResponse{
				IsDeliverable: true,
				Email:         "email@email.com",
				AuthTokens: []*notifyd.AuthToken{
					{Scope: email.MuteAuthScope, Token: "token_value1"},
					{Scope: email.MuteListScope, Token: "token_value2"},
					{Scope: email.EmailReplyScope, Token: "token_value3"},
				},
			},
			err: nil,
		},
		{
			name: "when the reqeust fails",
			res:  &notifyd.GetDeliverEmailDataResponse{},
			err:  errors.New("oops"),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			tenant := tenancy.NewSingleTenant()
			apiMock := api_client.NewNotifydAPIMock(t)
			apiMock.On("GetDeliverEmailData", mock.Anything, tenant, &req).Return(test.res, test.err)
			checker := checker{telem: logs.NullTelem, notifydAPIClient: apiMock}

			request := &EmailDeliveryRequest{
				UserID:         int64(req.UserId),
				OrganizationID: int64(req.OrganizationId),
				NotificationID: notificationID,
				MatchData:      matchData,
			}
			result, err := checker.GetDeliverEmailData(ctx, tenant, request)
			if test.err != nil {
				r.ErrorIs(err, test.err)
				r.False(result.IsDeliverable)
				r.Empty(result.Email)
				r.Equal("unexpected error", result.NotDeliverableReason)
			} else {
				r.Equal(test.res.Error, result.NotDeliverableReason)
				r.Equal(test.res.IsDeliverable, result.IsDeliverable)
				r.Equal(test.res.Email, result.Email)
				if result.IsDeliverable {
					r.Len(result.AuthTokens, 3)
					r.Equal(test.res.AuthTokens[0].Scope, result.AuthTokens[0].Scope)
					r.Equal(test.res.AuthTokens[0].Token, result.AuthTokens[0].Token)
					r.Equal(test.res.AuthTokens[1].Scope, result.AuthTokens[1].Scope)
					r.Equal(test.res.AuthTokens[1].Token, result.AuthTokens[1].Token)
					r.Equal(test.res.AuthTokens[2].Scope, result.AuthTokens[2].Scope)
					r.Equal(test.res.AuthTokens[2].Token, result.AuthTokens[2].Token)
				} else {
					r.Empty(result.AuthTokens)
				}
			}
		})
	}
}

func Test_buildGetDeliverEmailRequest(t *testing.T) {
	notificationID, _ := structpb.NewStruct(map[string]interface{}{
		"notification_id": "",
	})
	tests := []struct {
		name           string
		userID         int32
		organizationID int32
		matchData      map[string]interface{}
	}{
		{
			name:           "Builds correct  GetDeliverEmailRequest",
			userID:         1,
			organizationID: 2,
			matchData: map[string]interface{}{
				"subject_type": "GistComment",
				"trigger":      "create",
				"topics": []interface{}{
					map[string]interface{}{"type": "gist", "value": "123"},
				},
				"attributes": []interface{}{
					map[string]interface{}{"name": "watch_activity", "value": "true"},
				},
			},
		},
	}

	r := require.New(t)

	for _, test := range tests {
		matchDataStruct, err := structpb.NewStruct(test.matchData)
		r.NoError(err)

		request := &EmailDeliveryRequest{
			UserID:         int64(test.userID),
			OrganizationID: int64(test.organizationID),
			NotificationID: notificationID,
			MatchData:      matchDataStruct,
		}
		getDeliverEmailRequest := buildDeliverEmailProto(request)
		r.Equal(test.userID, getDeliverEmailRequest.UserId)
		r.Equal(test.organizationID, getDeliverEmailRequest.OrganizationId)
		r.Len(getDeliverEmailRequest.AuthTokenRequests, 3)
		r.Equal(email.MuteAuthScope, getDeliverEmailRequest.AuthTokenRequests[0].Scope)
		r.Equal(matchDataStruct, getDeliverEmailRequest.AuthTokenRequests[0].Data)
		r.Equal(email.MuteListScope, getDeliverEmailRequest.AuthTokenRequests[1].Scope)
		r.Equal(matchDataStruct, getDeliverEmailRequest.AuthTokenRequests[1].Data)
	}
}

func TestBatchCheckNotifyPolicy(t *testing.T) {
	r := require.New(t)
	notifydAPIMock := new(api_client.NotifydAPIMock)

	checker := checker{telem: logs.NullTelem, notifydAPIClient: notifydAPIMock}
	ctx := context.Background()

	req := notifyd.BatchCheckNotifyPolicyRequest{
		Context: &notifyd.ShouldNotifyRequestContext{
			RepositoryId: &wrappers.Int64Value{Value: int64(2)},
			ActorId:      int32(1),
		},
		Recipients: []*notifyd.Recipient{
			{
				UserId:  int32(123),
				Reasons: []*notifyd.Reason{{Name: "mention"}, {Name: "assign"}},
			},
			{
				UserId:  int32(321),
				Reasons: []*notifyd.Reason{{Name: "mention"}, {Name: "assign"}},
			},
		},
	}
	resp := notifyd.BatchCheckNotifyPolicyResponse{
		Responses: []*notifyd.CheckNotifyPolicyResponse{
			{
				UserId: 123,
				Notify: true,
				Error:  "",
			},
			{
				UserId: 321,
				Notify: false,
				Error:  "error",
			},
		},
	}
	// Protobufs can't be compared with reflect.DeepEqual() which mock uses by default,
	// so we use a custom matcher function using proto.Equal()
	// see https://github.com/osrg/gobgp/issues/1952
	reqMatchFunc := func(actualReq *notifyd.BatchCheckNotifyPolicyRequest) bool {
		sort.Slice(actualReq.Recipients, func(i, j int) bool { return actualReq.Recipients[i].UserId < actualReq.Recipients[j].UserId })
		return proto.Equal(actualReq, &req)
	}
	tenant := tenancy.NewSingleTenant()
	notifydAPIMock.On("BatchCheckNotifyPolicy", ctx, tenant, mock.MatchedBy(reqMatchFunc)).Return(&resp, nil)

	recipients := notify.RecipientIDToReasons{
		123: []string{"mention", "assign"},
		321: []string{"mention", "assign"},
	}
	result, err := checker.BatchCheckNotifyPolicy(ctx, tenant, recipients, req.Context)
	r.NoError(err)
	r.True(result.UserIDToCheckResult[123].IsDeliverable)
	r.False(result.UserIDToCheckResult[321].IsDeliverable)
	r.Equal("", result.NotDeliverableBatchReason)

	notifydAPIMock.AssertExpectations(t)
}

func TestBatchCheckIgnoredRepository(t *testing.T) {
	r := require.New(t)
	notifydAPIMock := api_client.NewNotifydAPIMock(t)

	checker := checker{telem: logs.NullTelem, notifydAPIClient: notifydAPIMock}
	ctx := context.Background()

	repositoryID := int64(2)
	req := notifyd.BatchCheckIgnoredRepositoryRequest{
		RepositoryId: &wrappers.Int64Value{Value: repositoryID},
		Recipients: []*notifyd.Recipient{
			{
				UserId:  int32(123),
				Reasons: []*notifyd.Reason{{Name: "mention"}, {Name: "assign"}},
			},
			{
				UserId:  int32(321),
				Reasons: []*notifyd.Reason{{Name: "mention"}, {Name: "assign"}},
			},
		},
	}
	resp := notifyd.BatchCheckIgnoredRepositoryResponse{
		Responses: []*notifyd.CheckNotifyPolicyResponse{
			{
				UserId: 123,
				Notify: true,
				Error:  "",
			},
			{
				UserId: 321,
				Notify: false,
				Error:  "ignoring repository",
			},
		},
	}
	// Protobufs can't be compared with reflect.DeepEqual() which mock uses by default,
	// so we use a custom matcher function using proto.Equal()
	// see https://github.com/osrg/gobgp/issues/1952
	reqMatchFunc := func(actualReq *notifyd.BatchCheckIgnoredRepositoryRequest) bool {
		sort.Slice(actualReq.Recipients, func(i, j int) bool { return actualReq.Recipients[i].UserId < actualReq.Recipients[j].UserId })
		return proto.Equal(actualReq, &req)
	}
	tenant := tenancy.NewSingleTenant()
	notifydAPIMock.On("BatchCheckIgnoredRepository", ctx, tenant, mock.MatchedBy(reqMatchFunc)).Return(&resp, nil)

	recipients := notify.RecipientIDToReasons{
		123: []string{"mention", "assign"},
		321: []string{"mention", "assign"},
	}
	result, err := checker.BatchCheckIgnoredRepository(ctx, tenant, repositoryID, recipients)
	r.NoError(err)
	r.True(result.UserIDToCheckResult[123].IsDeliverable)
	r.False(result.UserIDToCheckResult[321].IsDeliverable)
	r.Equal("", result.NotDeliverableBatchReason)
}
