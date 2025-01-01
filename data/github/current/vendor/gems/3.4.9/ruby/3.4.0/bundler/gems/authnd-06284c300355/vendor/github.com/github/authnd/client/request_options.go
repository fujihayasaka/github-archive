package client

import (
	"context"
	"net/http"
	"strconv"

	"github.com/twitchtv/twirp"
)

type RequestOption func(context.Context) context.Context

// WithTenant adds headers for the tenant ID and Shortcode to the outbound request.
//
// For Proxima, either WithTenant or WithTenantSlug is required.  WithTenant is preferred, as it is more
// performant, because it avoids additional MySQL lookups, and should be used by all clients downstream of Dotcom.
// Only services with public APIs (lacking ID and Shortcode) should use WithTenantSlug.
//
// In Dotcom/GHES, the tenant headers are discarded on the server-side.
func WithTenant(id int, shortcode string) RequestOption {
	return withHeaders(map[string]string{
		"X-GitHub-Tenant-ID":        strconv.Itoa(id),
		"X-GitHub-Tenant-Shortcode": shortcode,
	})
}

// WithTenantSlug adds headers for the tenant Slug to the outbound request.
//
// For Proxima, either WithTenant or WithTenantSlug is required.  WithTenant is preferred, as it is more
// performant, because it avoids additional MySQL lookups, and should be used by all clients downstream of Dotcom.
// Only services with public APIs (lacking ID and Shortcode) should use WithTenantSlug.
//
// In Dotcom/GHES, the tenant headers are discarded on the server-side.
func WithTenantSlug(slug string) RequestOption {
	return withHeaders(map[string]string{
		"X-GitHub-Tenant": slug,
	})
}

func withHeaders(kv map[string]string) RequestOption {
	return func(ctx context.Context) context.Context {
		header, ok := twirp.HTTPRequestHeaders(ctx)
		if !ok {
			header = make(http.Header)
		}

		for k, v := range kv {
			header.Add(k, v)
		}

		rctx, err := twirp.WithHTTPRequestHeaders(ctx, header)
		if err != nil {
			// Because we control the headers being added, this function cannot error. If it should happen to error
			// (i.e. because of a bug in our client), panicing is better than failing silently.
			panic(err)
		}
		return rctx
	}

}
