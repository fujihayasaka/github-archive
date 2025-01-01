package transport

import (
	"context"
	"errors"

	"github.com/github/attester/pkg/service"
	"github.com/twitchtv/twirp"
)

var ErrUnsupportedClient = twirp.InternalError("client ID does not match any supported client")

// GetTwirpError converts known service errors into their corresponding twirp.Error
func getTwirpError(e error) twirp.Error {
	var be *service.BadRequestError
	if errors.As(e, &be) {
		return twirp.WrapError(twirp.InvalidArgument.Error(be.Error()), be)
	}

	return twirp.InternalErrorWith(e)
}

// Twirp interceptor to translate service errors into the appropriate twirp
// error. Anything which is already a twirp error is passed through unchanged.
// Twirp ultimately expect all errors to be Twirp errors, if they are not they
// will be converted to an InternalError. This is our last opportunity to map
// our internal errors to the appropriate Twirp error and ensure that the most
// appropriate status code is returned.
func translateServiceErrorInterceptor() twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			resp, err := next(ctx, req)

			if err != nil {
				// If the error is not a twirp error, convert it to a twirp error
				var twerr twirp.Error
				if !errors.As(err, &twerr) {
					err = getTwirpError(err)
				}
			}

			return resp, err
		}
	}
}
