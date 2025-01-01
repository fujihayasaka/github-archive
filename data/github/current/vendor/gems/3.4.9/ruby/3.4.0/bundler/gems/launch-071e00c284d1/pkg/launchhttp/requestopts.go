package launchhttp

import (
	"context"
	"net/http"

	"github.com/github/launch/observability/azpcorrelation"
)

const ActionsServiceUserAgent = "GitHubServices service:actions"

// RequestOption is used to define how an *http.Request should be formed
type RequestOption func(req *http.Request) error

// WithADNCorrelationHeaders adds ADN correlation headers to the request
func WithADNCorrelationHeaders(ctx context.Context) RequestOption {
	e2eID := azpcorrelation.GetOrMakeVSSCorrelationID(ctx)
	orchestrationID := azpcorrelation.GetVSSOrchestrationID(ctx)

	return func(req *http.Request) error {
		req.Header.Set(azpcorrelation.UserAgentHeaderName, ActionsServiceUserAgent)
		req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, e2eID)

		if orchestrationID != "" {
			req.Header.Set(azpcorrelation.VSSOrchestrationIDHeaderName, orchestrationID)
		}
		return nil
	}
}

// WithAuthentication is used to authenticate some HTTP request by passing a custom
// RequestOption
func WithAuthentication(authF RequestOption) RequestOption {
	return func(req *http.Request) error {
		return authF(req)
	}
}

// WithBearerToken sets the Authorization header with the provided Bearer token
func WithBearerToken(token string) RequestOption {
	return func(req *http.Request) error {
		req.Header.Add("Authorization", "Bearer "+token)
		return nil
	}
}

// WithAccessToken sets the Authorization header with the provided personal access token
func WithAccessToken(token string) RequestOption {
	return func(req *http.Request) error {
		req.Header.Add("Authorization", "Token "+token)
		return nil
	}
}

// WithContentType overrides the content type for a request
func WithContentType(contentType string) RequestOption {
	return func(req *http.Request) error {
		req.Header.Set("Content-Type", contentType)
		return nil
	}
}

// WithHeaders adds headers to the request overwriting any existing headers if there is a collision
func WithHeaders(headers map[string]string) RequestOption {
	return func(req *http.Request) error {
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		return nil
	}
}

// WithJSONContentType sets the content type for a request
func WithJSONContentType() RequestOption {
	return WithContentType("application/json")
}

// WithJSONPatchContentType sets the Content Type to json-patch
func WithJSONPatchContentType() RequestOption {
	return WithContentType("application/json-patch+json")
}
