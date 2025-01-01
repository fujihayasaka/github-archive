package ratelimit

import (
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRateLimited(t *testing.T) {
	tests := []struct {
		name          string
		statusCode    int
		headers       map[string]string
		rateLimited   bool
		rateLimitType rateLimitType
	}{
		{
			name:       "rate limit headers ignored for non-403s",
			statusCode: 429,
			headers: map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			},
			rateLimited: false,
		},
		{
			name:        "rate limit headers not set",
			statusCode:  403,
			headers:     map[string]string{},
			rateLimited: false,
		},
		{
			name:       "rate limit not exceeded",
			statusCode: 403,
			headers: map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "59",
			},
			rateLimited: false,
		},
		{
			name:       "primary rate limit exceeded",
			statusCode: 403,
			headers: map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			},
			rateLimited: true,
		},
		{
			name:       "secondary rate limit exceeded",
			statusCode: 403,
			headers: map[string]string{
				"Retry-After": "1",
			},
			rateLimited: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			header := make(http.Header)
			for k, v := range tt.headers {
				header.Set(k, v)
			}

			result := RateLimited(tt.statusCode, header)
			assert.Equal(t, tt.rateLimited, result)
		})
	}
}
