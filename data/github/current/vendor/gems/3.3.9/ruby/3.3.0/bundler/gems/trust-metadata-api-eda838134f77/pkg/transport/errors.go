package transport

import (
	"errors"

	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/twitchtv/twirp"
)

var ErrNoMatchingAttestations = twirp.NotFoundError("no matching attestations found")
var ErrNoSubjectDigest = twirp.InvalidArgumentError("subject_digest", "must be provided")
var ErrUnsupportedClient = twirp.InternalError("client ID does not match any supported client")

// GetTwirpError converts an error into a twirp.Error if the error is a known
func GetTwirpError(e error) twirp.Error {
	var ua service.InternalError
	if errors.As(e, &ua) {
		return twirp.WrapError(twirp.Internal.Error(ua.ClientFacingError()), ua)
	}
	var be service.BadRequestError
	if errors.As(e, &be) {
		return twirp.WrapError(twirp.InvalidArgument.Error(be.ClientFacingError()), be)
	}
	var ce service.ConflictError
	if errors.As(e, &ce) {
		return twirp.WrapError(twirp.AlreadyExists.Error(ce.ClientFacingError()), ce)
	}
	var nfe service.NotFoundError
	if errors.As(e, &nfe) {
		return twirp.WrapError(twirp.NotFound.Error(nfe.ClientFacingError()), nfe)
	}
	return twirp.WrapError(twirp.InternalError("internal error"), e)
}
