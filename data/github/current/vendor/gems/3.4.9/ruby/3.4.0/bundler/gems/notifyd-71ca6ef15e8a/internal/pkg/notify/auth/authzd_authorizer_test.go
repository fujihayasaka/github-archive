package auth

import (
	"context"
	"testing"

	authzdProto "github.com/github/authzd/pkg/proto"
	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
)

func TestAuthorizeRecipients(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()

	initiatorID := int64(100)
	authzdClientMock := NewAuthzdClientMock(t)

	decisions := []*authzdProto.Decision{
		{Result: authzdProto.Result_ALLOW},
		{Result: authzdProto.Result_DENY},
		{Result: authzdProto.Result_INDETERMINATE},
		{Result: authzdProto.Result_NOT_APPLICABLE},
		{Result: authzdProto.Result_ALLOW},
	}
	batchDecision := authzdProto.BatchDecision{
		Decisions: decisions,
	}
	userIDs := make([]int64, len(decisions))
	requests := make([]*authzdProto.Request, len(decisions))
	versionAttribute := authzdProto.Attribute{
		Id:    "version",
		Value: authzdProto.NewInt64Value(2),
	}
	actionAttribute := authzdProto.Attribute{
		Id:    "action",
		Value: authzdProto.NewStringValue("receive_notification"),
	}
	actorTypeAttribute := authzdProto.Attribute{
		Id:    "actor.type",
		Value: authzdProto.NewStringValue("User"),
	}
	initiatorIDAttribute := authzdProto.Attribute{
		Id:    "notification.initiator.id",
		Value: authzdProto.NewInt64Value(initiatorID),
	}
	subjectIDAttribute := authzdProto.Attribute{
		Id:    "subject.id",
		Value: authzdProto.NewInt64Value(1234),
	}
	subjectTypeAttribute := authzdProto.Attribute{
		Id:    "subject.type",
		Value: authzdProto.NewStringValue("IssueComment"),
	}
	for idx := range decisions {
		userID := int64(idx + 1)
		userIDs[idx] = userID
		attributes := []*authzdProto.Attribute{
			&versionAttribute,
			&actionAttribute,
			&actorTypeAttribute,
			&initiatorIDAttribute,
			&subjectIDAttribute,
			&subjectTypeAttribute,
			{
				Id:    "actor.id",
				Value: authzdProto.NewInt64Value(userID),
			},
		}
		requests[idx] = &authzdProto.Request{Attributes: attributes}
	}

	expectedBatchRequest := authzdProto.BatchRequest{Requests: requests}
	tenant := tenancy.NewSingleTenant()
	// Protobufs can't be compared with reflect.DeepEqual() which mock uses by default,
	// so we use a custom matcher function using proto.Equal()
	// see https://github.com/osrg/gobgp/issues/1952
	batchRequestMatchFunc := func(request *authzdProto.BatchRequest) bool {
		return proto.Equal(request, &expectedBatchRequest)
	}
	authzdClientMock.On("BatchAuthorize", mock.Anything, tenant, mock.MatchedBy(batchRequestMatchFunc)).Return(&batchDecision, nil)

	authorizer := AuthzdAuthorizer{authzdClientMock}

	wrappedSubjectIDAttribute, err := anypb.New(&subjectIDAttribute)
	r.NoError(err)
	wrappedSubjectTypeAttribute, err := anypb.New(&subjectTypeAttribute)
	r.NoError(err)
	commonAttributes := []*anypb.Any{
		wrappedSubjectIDAttribute,
		wrappedSubjectTypeAttribute,
	}
	checks, err := authorizer.AuthorizeRecipients(ctx, tenant, initiatorID, userIDs, commonAttributes)
	r.NoError(err)

	var authorized []int64
	var unauthorized []int64
	for _, check := range checks {
		if check.IsAllowed() {
			authorized = append(authorized, check.UserID)
		} else {
			unauthorized = append(unauthorized, check.UserID)
		}
	}

	r.ElementsMatch(authorized, []int64{1, 5})
	r.ElementsMatch(unauthorized, []int64{2, 3, 4})
}
