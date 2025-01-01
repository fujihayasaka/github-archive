package twirputils

import (
	"context"
	"net/http"

	"github.com/twitchtv/twirp"
)

// ContextWithTwirpHeader stores a Twirp specific http.Header in the given context.Context.
// The header will contain the given key/value pair and will be included in all Twirp requests made using the returned context.Context.
// If the given context.Context already contains a Twirp http.Header, the given key/value pair will be added to it
// or overwrite the existing value for the key if it already exists.
func ContextWithTwirpHeader(ctx context.Context, key, value string) (context.Context, error) {

	header, ok := twirp.HTTPRequestHeaders(ctx)
	if !ok {
		header = make(http.Header)
	}

	header.Set(key, value)

	return twirp.WithHTTPRequestHeaders(ctx, header)
}
