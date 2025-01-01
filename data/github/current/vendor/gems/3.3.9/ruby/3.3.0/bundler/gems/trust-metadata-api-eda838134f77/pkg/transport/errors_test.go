package transport

import (
	"errors"
	"testing"

	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
)

func TestGetTwirpError(t *testing.T) {
	cause := errors.New("1")

	internalError := service.NewInternalError(cause)
	twirpInternalError := GetTwirpError(internalError)
	assert.ErrorIs(t, internalError, cause)
	assert.Equal(t, internalError.Error(), "InternalError: 1")
	assert.ErrorIs(t, twirpInternalError, cause)
	assert.ErrorIs(t, twirpInternalError, internalError)
	assert.Equal(t, twirpInternalError.Code(), twirp.Internal)
	assert.Equal(t, twirpInternalError.Error(), "twirp error internal: internal error")

	badRequestError := service.NewBadRequestError(cause)
	twirpBadRequestError := GetTwirpError(badRequestError)
	assert.ErrorIs(t, badRequestError, cause)
	assert.Equal(t, badRequestError.Error(), "BadRequestError: 1")
	assert.ErrorIs(t, twirpBadRequestError, cause)
	assert.ErrorIs(t, twirpBadRequestError, badRequestError)
	assert.Equal(t, twirpBadRequestError.Code(), twirp.InvalidArgument)
	assert.Equal(t, twirpBadRequestError.Error(), "twirp error invalid_argument: 1")

	conflictError := service.NewConflictError(cause)
	twirpConflictError := GetTwirpError(conflictError)
	assert.ErrorIs(t, conflictError, cause)
	assert.Equal(t, conflictError.Error(), "ConflictError: 1")
	assert.ErrorIs(t, twirpConflictError, cause)
	assert.ErrorIs(t, twirpConflictError, conflictError)
	assert.Equal(t, twirpConflictError.Code(), twirp.AlreadyExists)
	assert.Equal(t, twirpConflictError.Error(), "twirp error already_exists: 1")
}
