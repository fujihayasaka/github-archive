package stages

import (
	"context"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/auth"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_AuthorizeRecipients(t *testing.T) {
	ctx := context.Background()

	actorID := int64(100)

	recipientIDsToReasons := notify.RecipientIDToReasons{
		1: []string{"manual", "author"},
		2: []string{"manual"},
		3: []string{"manual"},
		4: []string{"manual", "review_requested"},
		5: []string{"manual"},
	}
	msg := notify.Notification{ActorID: actorID}

	policyChecks := auth.PolicyCheckLookup{
		{
			UserID: 1,
			Status: auth.Allow,
		},
		{
			UserID: 2,
			Status: auth.Deny,
			Reason: "Deny",
		},
		{
			UserID: 3,
			Status: auth.Deny,
			Reason: "Deny",
		},
		{
			UserID: 4,
			Status: auth.Allow,
		},
		{
			UserID: 5,
			Status: auth.Deny,
			Reason: "Deny",
		},
	}

	authorizer := new(auth.AuthzdAuthorizerStub)
	authorizer.
		On("AuthorizeRecipients", mock.Anything, mock.Anything, actorID, []int64{1, 2, 3, 4, 5}, mock.Anything).
		Return(policyChecks, nil)

	stage := NewAuthorizeRecipientsStage(authorizer, clock.NewMock(), logs.NullTelem, stats.NullStatter)

	result, err := stage.AuthorizeRecipients(ctx, tenancy.NewSingleTenant(), recipientIDsToReasons, &msg)
	require.NoError(t, err)

	expected := notify.RecipientIDToReasons{
		1: []string{"manual", "author"},
		4: []string{"manual", "review_requested"},
	}

	require.Equal(t, expected, result)

	authorizer.AssertExpectations(t)
}
