package middleware

import (
	"net/http"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

type catalogServiceMiddleware struct {
	delegate       pb.HTTPClient
	catalogService string
}

// ApplyCatalogService wraps an HTTP client with middleware
// that sets the "Catalog-Service" header in requests
// uses the provided catalogService as the header value
func ApplyCatalogService(c pb.HTTPClient, catalogService string) pb.HTTPClient {
	return &catalogServiceMiddleware{
		delegate:       c,
		catalogService: catalogService,
	}
}

func (m *catalogServiceMiddleware) Do(req *http.Request) (*http.Response, error) {
	req.Header.Set("Catalog-Service", m.catalogService)
	return m.delegate.Do(req)
}
