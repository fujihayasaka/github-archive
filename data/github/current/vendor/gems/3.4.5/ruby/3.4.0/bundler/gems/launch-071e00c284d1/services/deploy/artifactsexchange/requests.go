package artifactsexchange

import (
	"errors"
	"net/url"
)

// Validate returns an error if any of the request parameters are invalid.
func (r *ExchangeURLRequest) Validate() error {
	if r.UnauthenticatedUrl == "" {
		return errors.New("missing unauthenticated url")
	}

	if r.RepositoryId == nil {
		return errors.New("missing repository id")
	}

	_, err := url.Parse(r.UnauthenticatedUrl)
	if err != nil {
		return errors.New("invalid url provided")
	}

	return nil
}
