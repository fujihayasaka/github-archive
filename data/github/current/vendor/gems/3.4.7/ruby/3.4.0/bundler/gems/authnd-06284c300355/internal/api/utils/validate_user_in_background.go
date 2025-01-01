package utils

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common/models"
	"github.com/pkg/errors"
)

var UserValidationError_UserSuspended = errors.New("user is suspended")

type UserLookupFunc func(ctx context.Context) (*models.User, error)

type userValidation struct {
	User *models.User
	Err  error
}

type UserValidationOption func(*options)

type options struct {
	checkSuspension bool
}

func defaultOptions() options {
	return options{
		checkSuspension: true,
	}
}

func AllowSuspendedUsers() UserValidationOption {
	return func(c *options) {
		c.checkSuspension = false
	}
}

type AwaitUserValidationFunc func() (*models.User, error)

func ValidateUserInBackground(outerCtx context.Context, userLookupFunc UserLookupFunc, opts ...UserValidationOption) (AwaitUserValidationFunc, context.CancelFunc) {
	options := defaultOptions()
	for _, opt := range opts {
		opt(&options)
	}

	respChan := make(chan *userValidation, 1)

	ctx, cancel := context.WithCancel(outerCtx)
	userValidationChan := make(chan *userValidation, 1)
	go func() {
		defer cancel()

		user, err := userLookupFunc(ctx)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			userValidationChan <- &userValidation{
				Err: errors.Wrap(err, "error looking up user"),
			}
			return
		}

		if user == nil {
			userValidationChan <- &userValidation{}
			return
		}
		if options.checkSuspension && user.IsSuspended() {
			userValidationChan <- &userValidation{
				Err: UserValidationError_UserSuspended,
			}
			return
		}
		userValidationChan <- &userValidation{
			User: user,
		}
	}()

	// make sure to keep an eye on the outer context
	go func() {
		select {
		case <-outerCtx.Done():
			cancel()
			respChan <- &userValidation{
				Err: outerCtx.Err(),
			}
		case r := <-userValidationChan:
			respChan <- r
		}
	}()

	return func() (*models.User, error) {
		userValidation := <-respChan
		return userValidation.User, userValidation.Err
	}, cancel
}
