package stages

import (
	"context"
	"testing"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/wrapperspb"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_ValidateDotcomRecipientPoliciesStage_ValidateIgnoredRepository_NotFoundError(t *testing.T) {
	checker := policy.NewCheckerMock(t)
	clock := clockpkg.NewMock()
	telem := logs.NullTelem
	statter := stats.NullStatter

	checker.
		On("BatchCheckIgnoredRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(policy.BatchCheckResult{}, twirp.NewError(twirp.InvalidArgument, "Repository not found"))

	stage := NewValidateDotcomRecipientPoliciesStage(checker, clock, telem, statter)

	notifyMessage := &schema_pb.Notify{
		Context: &schema_pb.Notify_Context{
			Trigger:      "create",
			RepositoryId: &wrapperspb.Int64Value{Value: 1},
		},
	}

	recipients := notify.RecipientIDToReasons{
		2: []string{"subscribed"},
	}

	msg := notify.PBToNotification(notifyMessage)
	recipients, err := stage.ValidateIgnoredRepository(context.Background(), tenancy.NewSingleTenant(), recipients, msg)

	require.NoError(t, err)
	require.Empty(t, recipients)
}

func Test_ValidateDotcomRecipientPoliciesStage_SkipMobileAuth(t *testing.T) {
	checker := policy.NewCheckerMock(t)
	clock := clockpkg.NewMock()
	telem := logs.NullTelem
	statter := stats.NullStatter

	stage := NewValidateDotcomRecipientPoliciesStage(checker, clock, telem, statter)

	notifyMessage := &schema_pb.Notify{
		NotificationId: "mobile-auth-request/user-1234123",
		Context: &schema_pb.Notify_Context{
			Trigger:      "create",
			RepositoryId: &wrapperspb.Int64Value{Value: 1},
		},
	}

	recipients := notify.RecipientIDToReasons{
		2: []string{"subscribed"},
	}

	msg := notify.PBToNotification(notifyMessage)
	recipients, err := stage.ValidateIgnoredRepository(context.Background(), tenancy.NewSingleTenant(), recipients, msg)

	require.NoError(t, err)
	require.Len(t, recipients, 1)
}

func Test_ValidateDotcomRecipientPoliciesStage_ValidateIgnoredRepository_MissingRecipientsError(t *testing.T) {
	checker := policy.NewCheckerMock(t)
	clock := clockpkg.NewMock()
	telem := logs.NullTelem
	statter := stats.NullStatter

	checker.
		On("BatchCheckIgnoredRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(policy.BatchCheckResult{}, twirp.NewError(twirp.InvalidArgument, "Too many recipients in list"))

	stage := NewValidateDotcomRecipientPoliciesStage(checker, clock, telem, statter)

	notifyMessage := &schema_pb.Notify{
		Context: &schema_pb.Notify_Context{
			Trigger:      "create",
			RepositoryId: &wrapperspb.Int64Value{Value: 1},
		},
	}

	recipients := notify.RecipientIDToReasons{}

	msg := notify.PBToNotification(notifyMessage)
	_, err := stage.ValidateIgnoredRepository(context.Background(), tenancy.NewSingleTenant(), recipients, msg)

	require.Error(t, err)
	require.True(t, errors.IsRetriable(err))
}

func Test_ValidateDotcomRecipientPoliciesStage_ValidateIgnoredRepository_SkipMobileAuth(t *testing.T) {
	checker := policy.NewCheckerMock(t)
	clock := clockpkg.NewMock()
	telem := logs.NullTelem
	statter := stats.NullStatter

	stage := NewValidateDotcomRecipientPoliciesStage(checker, clock, telem, statter)

	notifyMessage := &schema_pb.Notify{
		NotificationId: "mobile-auth-request/user-12312",
		Context: &schema_pb.Notify_Context{
			Trigger:      "create",
			RepositoryId: &wrapperspb.Int64Value{Value: 1},
		},
	}

	recipients := notify.RecipientIDToReasons{
		2: []string{"subscribed"},
	}

	msg := notify.PBToNotification(notifyMessage)
	_, err := stage.ValidateIgnoredRepository(context.Background(), tenancy.NewSingleTenant(), recipients, msg)

	require.NoError(t, err)
	require.Len(t, recipients, 1)
}
