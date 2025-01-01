package azp

import (
	"context"
	"time"
)

// URLExchangeClient is used for exchanging signed URLs.
type URLExchangeClient interface {
	GetAuthenticatedURL(ctx context.Context, url string) (*GetAuthenticatedURLResponse, error)
}

// GetAuthenticatedURLResponse is response returned from getting an authenticated step log
type GetAuthenticatedURLResponse struct {
	SignedContent *SignedContent `json:"signedContent"`
}

// SignedContent is the Authenticated URL and when it expires.
type SignedContent struct {
	URL              string    `json:"url"`
	SignatureExpires time.Time `json:"signatureExpires"`
}
