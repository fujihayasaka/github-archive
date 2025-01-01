package utils

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/models"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestValidateUserInBackgroundReturnsNilForUserIfLookupReturnsNils(t *testing.T) {
	ctx := context.Background()

	awaitUser, _ := ValidateUserInBackground(ctx, func(ctx context.Context) (*models.User, error) {
		return nil, nil
	})
	user, err := awaitUser()
	require.Nil(t, err)
	require.Nil(t, user)
}

func TestValidateUserInBackgroundReturnsNilUserAndNilErrorIfLookupReturnsMysqlErrNoRows(t *testing.T) {
	ctx := context.Background()

	awaitUser, _ := ValidateUserInBackground(ctx, func(ctx context.Context) (*models.User, error) {
		return nil, sql.ErrNoRows
	})
	user, err := awaitUser()
	require.Nil(t, err)
	require.Nil(t, user)
}

func TestValidateUserInBackgroundReturnsSuspendedErrorIfUserIsMarkedAsSuspended(t *testing.T) {
	ctx := context.Background()

	awaitUser, _ := ValidateUserInBackground(ctx, func(ctx context.Context) (*models.User, error) {
		return &models.User{
			ID:          123,
			SuspendedAt: models.NullMysqlDateTimeFromTime(time.Now().Add(-time.Hour)),
		}, nil
	})
	user, err := awaitUser()
	require.Equal(t, UserValidationError_UserSuspended, err)
	require.Nil(t, user)
}

func TestValidateUserInBackgroundReturnsUser(t *testing.T) {
	ctx := context.Background()
	returnedUser := &models.User{
		ID: 123,
	}

	awaitUser, _ := ValidateUserInBackground(ctx, func(ctx context.Context) (*models.User, error) {
		return returnedUser, nil
	})
	user, err := awaitUser()
	require.Nil(t, err)
	require.NotNil(t, user)
}

func TestValidateUserInBackgroundReturnsSuspendedUserIfOptOutOfSuspensionCheck(t *testing.T) {
	ctx := context.Background()
	returnedUser := &models.User{
		ID:          123,
		SuspendedAt: models.NullMysqlDateTimeFromTime(time.Now().Add(-time.Hour)),
	}

	awaitUser, _ := ValidateUserInBackground(ctx, func(ctx context.Context) (*models.User, error) {
		return returnedUser, nil
	}, AllowSuspendedUsers())
	user, err := awaitUser()
	require.Nil(t, err)
	require.NotNil(t, user)
}

func TestValidateUserInBackgroundCanCancelLookup(t *testing.T) {
	expectedErr := errors.New("expected err")
	ctx := context.Background()
	awaitUser, cancel := ValidateUserInBackground(ctx, func(innerCtx context.Context) (*models.User, error) {
		// mimic a long-running query that depends on the inner context
		<-innerCtx.Done()
		return nil, expectedErr
	})
	cancel()
	user, err := awaitUser()
	require.Nil(t, user)
	require.ErrorIs(t, err, expectedErr)
}

func TestValidateUserInBackgroundRespectsOuterCxtCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())

	awaitUser, _ := ValidateUserInBackground(ctx, func(innerCtx context.Context) (*models.User, error) {
		// mimic a long-running query that depends on the inner context
		<-innerCtx.Done()
		return nil, errors.New("unexpected error")
	})

	// cancel the outer context
	cancel()

	// wait for the user promise to return
	user, err := awaitUser()

	// we expect nil for user
	// and a context cancellation error if the outer context was cancelled
	require.Nil(t, user)
	require.ErrorIs(t, err, context.Canceled)
}
