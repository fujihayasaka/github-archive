package ratelimit

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

func TestResponseValidator(t *testing.T) {
	// Chain to another response validator. This will be the common case.
	nextValidator := httpclient.DefaultValidator()

	tests := []struct {
		name              string
		statusCode        int
		headers           map[string]string
		respBody          string
		expectedResult    int
		expectedError     string
		expectedReportErr error
		expectedStatKey   string
		expectedStatTags  statter.Tags
	}{
		{
			name:           "successful response",
			statusCode:     200,
			respBody:       "42",
			expectedResult: 42,
		},
		{
			name:          "non-rate limit error response",
			statusCode:    404,
			expectedError: "response code error 404",
		},
		{
			name:          "403 response with no rate limit headers",
			statusCode:    403,
			respBody:      `{"message":"Repository access blocked","block":{"reason":"tos","created_at":"2022-12-28T22:50:19Z","html_url":"https://github.com/tos"}}`,
			expectedError: "response code error 403",
		},
		{
			name:       "primary rate limit exceeded response",
			statusCode: 403,
			headers: map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			},
			respBody:          `{"message": "API rate limit exceeded for installation ID 1337.", "documentation_url": "https://docs.github.com"}`,
			expectedError:     "GitHub rate limit exceeded: API rate limit exceeded for installation ID 1337.",
			expectedReportErr: New("GitHub rate limit exceeded: API rate limit exceeded for installation ID 1337.", 403),
			expectedStatKey:   "github_rate_limit_exceeded",
			expectedStatTags:  statter.Tags{"scoped_to_customer": "false", "operation": "GetFoo", "rate_limit_type": "primary"},
		},
		{
			name:       "secondary rate limit exceeded response",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			respBody:          `{"message": "You have exceeded a secondary rate limit.", "documentation_url": "https://docs.github.com"}`,
			expectedError:     "GitHub rate limit exceeded: You have exceeded a secondary rate limit.",
			expectedReportErr: New("GitHub rate limit exceeded: You have exceeded a secondary rate limit.", 403),
			expectedStatKey:   "github_rate_limit_exceeded",
			expectedStatTags:  statter.Tags{"scoped_to_customer": "false", "operation": "GetFoo", "rate_limit_type": "secondary"},
		},
		{
			name:       "rate limit exceeded response without response body",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			expectedError:     "GitHub rate limit exceeded",
			expectedReportErr: New("GitHub rate limit exceeded", 403),
			expectedStatKey:   "github_rate_limit_exceeded",
			expectedStatTags:  statter.Tags{"scoped_to_customer": "false", "operation": "GetFoo", "rate_limit_type": "secondary"},
		},
		{
			name:       "rate limit exceeded response with non-json response body",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			respBody:          `Go Away`,
			expectedError:     "GitHub rate limit exceeded: Go Away",
			expectedReportErr: New("GitHub rate limit exceeded: Go Away", 403),
			expectedStatKey:   "github_rate_limit_exceeded",
			expectedStatTags:  statter.Tags{"scoped_to_customer": "false", "operation": "GetFoo", "rate_limit_type": "secondary"},
		},
		{
			name:       "rate limit exceeded response without message field",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			respBody:          `{"go": "away"}`,
			expectedError:     `GitHub rate limit exceeded: {"go": "away"}`,
			expectedReportErr: New(`GitHub rate limit exceeded: {"go": "away"}`, 403),
			expectedStatKey:   "github_rate_limit_exceeded",
			expectedStatTags:  statter.Tags{"scoped_to_customer": "false", "operation": "GetFoo", "rate_limit_type": "secondary"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Using a http server and client to test the response validator with a realistic http.Response object.
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				assert.Equal(t, req.Method, "GET")

				for k, v := range tt.headers {
					w.Header().Set(k, v)
				}
				w.WriteHeader(tt.statusCode)
				if tt.respBody != "" {
					w.Write([]byte(tt.respBody))
				}
			}))
			defer server.Close()

			ctx := context.Background()
			obs, log, stat := observability.NewMockedObservability()
			httpClient := httpclient.New(http.DefaultClient)
			fooClient := &fooClient{httpClient, server.URL}

			if tt.expectedReportErr != nil {
				log.EXPECT().Report(ctx, tt.expectedReportErr, mock.Anything, mock.Anything, mock.Anything).Once()
			}

			if tt.expectedStatKey != "" {
				stat.EXPECT().Counter(mock.Anything, tt.expectedStatKey, tt.expectedStatTags, int64(1)).Once()
			}

			res, err := fooClient.GetFoo(ctx, obs, nextValidator)
			if tt.expectedError != "" {
				assert.EqualError(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
			}
			assert.Equal(t, tt.expectedResult, res)

			log.AssertExpectations(t)
			stat.AssertExpectations(t)
		})
	}
}

// TestResponseValidatorWithoutNext tests the response validator without a chained validator.
// The response validator should work without a chained validator. However it doesn't marshal
// non-rate limiting responses to errors.
func TestResponseValidatorWithoutNext(t *testing.T) {
	var nextValidator httpclient.ResponseValidator = nil

	tests := []struct {
		name           string
		statusCode     int
		headers        map[string]string
		respBody       string
		expectedResult int
		expectedError  string
	}{
		{
			name:           "successful response",
			statusCode:     200,
			respBody:       "42",
			expectedResult: 42,
		},
		{
			// 404 isn't marshaled to an error without a chained response validator
			name:           "non-rate limit error response",
			statusCode:     404,
			respBody:       "42",
			expectedResult: 42,
		},
		{
			name:           "403 response with no rate limit headers",
			statusCode:     403,
			respBody:       "42",
			expectedResult: 42,
		},
		{
			name:       "secondary rate limit exceeded response",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			respBody:      "42",
			expectedError: "GitHub rate limit exceeded: 42",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Using a http server and client to test the response validator with a realistic http.Response object.
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				assert.Equal(t, req.Method, "GET")

				for k, v := range tt.headers {
					w.Header().Set(k, v)
				}
				w.WriteHeader(tt.statusCode)
				if tt.respBody != "" {
					w.Write([]byte(tt.respBody))
				}
			}))
			defer server.Close()

			ctx := context.Background()
			obs := observability.NewTestObservability()
			httpClient := httpclient.New(http.DefaultClient)
			fooClient := &fooClient{httpClient, server.URL}

			res, err := fooClient.GetFoo(ctx, obs, nextValidator)
			if tt.expectedError != "" {
				assert.EqualError(t, err, tt.expectedError)
			} else {
				require.NoError(t, err)
			}
			assert.Equal(t, tt.expectedResult, res)
		})
	}
}

// A simple launchhttp-based client for testing the response validator.
type fooClient struct {
	httpclient *httpclient.Client
	url        string
}

func (c *fooClient) GetFoo(ctx context.Context, obs *observability.Observability, nextValidator httpclient.ResponseValidator) (int, error) {
	var dst int
	opName := "GetFoo"

	rv := ResponseValidator(ctx, obs, opName, false, nextValidator)
	err := c.httpclient.Do(ctx, opName, http.MethodGet, c.url, nil, &dst, httpclient.WithValidator(rv))
	return dst, err
}
