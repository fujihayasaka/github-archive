package ratelimit

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"

	"github.com/pkg/errors"

	gherr "github.com/github/launch/clients/github/errors"
)

const (
	// Rate limits enforced by Dotcom will have a 403 status code
	// If we receive a 429, that may indicate a GLB rate limit, which we won't handle here
	// https://cs.github.com/?scope=&q=org%3Agithub+429backend_rate_limited
	// https://github.com/github/ecosystem-api/issues/3476 tracks switching to 429 in a future API version
	rateLimitStatusCode      = http.StatusForbidden
	rateLimitHeader          = "X-RateLimit-Limit"
	ratelimitRemainingHeader = "X-RateLimit-Remaining"
	retryAfterHeader         = "Retry-After"
)

type rateLimitType string

const (
	noRateLimitType        rateLimitType = ""
	primaryRateLimitType   rateLimitType = "primary"
	secondaryRateLimitType rateLimitType = "secondary"
)

// RateLimited returns true if the response is a rate limit error from Dotcom
// This will check for both primary and secondary rate limits
// See https://thehub.github.com/epd/engineering/products-and-services/public-apis/rate-limits/ for more info
func RateLimited(sc int, header http.Header) bool {
	ok, _ := rateLimitedWithType(sc, header)
	return ok
}

func rateLimitedWithType(sc int, header http.Header) (bool, rateLimitType) {
	if sc != rateLimitStatusCode {
		return false, noRateLimitType
	}

	if header.Get(ratelimitRemainingHeader) == "0" {
		return true, primaryRateLimitType
	}

	if ra := header.Get(retryAfterHeader); ra != "" {
		return true, secondaryRateLimitType
	}

	return false, noRateLimitType
}

// readBodyRepeatable reads the response body and resets it so it can be read again
func readBodyRepeatable(res *http.Response) ([]byte, error) {
	if res.Body == nil {
		return nil, nil
	}

	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return nil, errors.Wrap(err, "reading body")
	}
	if err := res.Body.Close(); err != nil {
		return nil, errors.Wrap(err, "closing body")
	}

	// Reset the body so that it can be read again
	buf := bytes.NewReader(body)
	res.Body = io.NopCloser(buf)

	return body, nil
}

// errMsgFromBody extracts the error message from the GitHub API response body
func errMsgFromBody(body []byte) string {
	if body == nil {
		return ""
	}

	var er *gherr.ErrorResponse
	if err := json.Unmarshal(body, &er); err != nil {
		// fallback to logging the raw body so we have something to go on
		return string(body)
	}
	if er.Message == "" {
		return string(body)
	}
	return er.Message
}
