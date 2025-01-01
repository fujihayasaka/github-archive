package ghtwirp

import (
	"net/http"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/github/ratelimit"
	"github.com/github/launch/observability"

	"github.com/twitchtv/twirp"
)

func newRateLimitHandler(next HTTPClient, obs *observability.Observability) HTTPClient {
	return &rateLimitHandler{
		next: next,
		obs:  obs,
	}
}

type rateLimitHandler struct {
	next HTTPClient
	obs  *observability.Observability
}

func (trl *rateLimitHandler) Do(r *http.Request) (*http.Response, error) {
	resp, err := trl.next.Do(r)
	if err != nil {
		return nil, err
	}

	if ratelimit.RateLimited(resp.StatusCode, resp.Header) {
		operationName, ok := twirp.MethodName(r.Context())
		if !ok {
			return nil, errors.New("twirp method name not found")
		}

		// Twirp rate limit is enforced by client name and IP
		// So if we are hitting it, it will affect all customers
		scopedToCustomer := false

		ratelimit.ReportRateLimiting(r.Context(), trl.obs, resp, operationName, scopedToCustomer)
		return nil, ratelimit.ErrorFromResponse(resp)
	}

	return resp, nil
}
