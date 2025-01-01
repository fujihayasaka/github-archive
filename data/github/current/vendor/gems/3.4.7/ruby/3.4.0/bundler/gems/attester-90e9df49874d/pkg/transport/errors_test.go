package transport

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/attester/pkg/service"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

func TestGetTwirpError(t *testing.T) {
	cause := errors.New("oops")

	badRequestError := service.NewBadRequestError(cause)
	twirpBadRequestError := getTwirpError(badRequestError)
	assert.ErrorIs(t, badRequestError, cause)
	assert.Equal(t, badRequestError.Error(), "oops")
	assert.ErrorIs(t, twirpBadRequestError, cause)
	assert.ErrorIs(t, twirpBadRequestError, badRequestError)
	assert.Equal(t, twirpBadRequestError.Code(), twirp.InvalidArgument)
	assert.Equal(t, twirpBadRequestError.Error(), "twirp error invalid_argument: oops")
}

func TestErrorInterceptorWithTwirpError(t *testing.T) {
	expectedErr := twirp.InternalError("test")
	method := func(_ context.Context, _ interface{}) (interface{}, error) {
		return nil, expectedErr
	}

	interceptor := translateServiceErrorInterceptor()
	_, err := interceptor(method)(context.Background(), nil)
	assert.Equal(t, expectedErr, err)
}

func TestErrorInterceptorWithServiceError(t *testing.T) {
	innerErr := service.NewBadRequestError(fmt.Errorf("test"))
	method := func(_ context.Context, _ interface{}) (interface{}, error) {
		return nil, innerErr
	}

	interceptor := translateServiceErrorInterceptor()
	_, err := interceptor(method)(context.Background(), nil)
	assert.NotEqual(t, innerErr, err)

	var twirpErr twirp.Error
	if errors.As(err, &twirpErr) {
		assert.Equal(t, twirp.ErrorCode("invalid_argument"), twirpErr.Code())
	} else {
		assert.Fail(t, "expected twirp error")
	}
}
