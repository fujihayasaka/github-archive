package observability

import (
	"context"
	"net/http"
	"net/url"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStatusCodeToCategoryName(t *testing.T) {
	assert.Equal(t, "2xx", HTTPStatusToCategoryName(200))
	assert.Equal(t, "5xx", HTTPStatusToCategoryName(523))
	assert.Equal(t, "invalid_status", HTTPStatusToCategoryName(-40))
	assert.Equal(t, "invalid_status", HTTPStatusToCategoryName(925))
	assert.Equal(t, "invalid_status", HTTPStatusToCategoryName(0))
}

func TestStatusForHTTPResult(t *testing.T) {
	assert.Equal(t, "non_http_error", statusForHTTPResult(0, errors.New("fail")))
	assert.Equal(t, "2xx", statusForHTTPResult(204, nil))
	assert.Equal(t, "non_http_error", statusForHTTPResult(1, errors.New("fail")))
}

func TestCountHTTPResult(t *testing.T) {
	obs := NewNullObservability()
	ctx := context.Background()
	ok := 200
	CountHTTPResult(ctx, obs, "srv", "op", 0, errors.New("boom"))
	CountHTTPResult(ctx, obs, "srv", "op", ok, errors.New("boom"))
	CountHTTPResult(ctx, obs, "srv", "op", ok, nil)
}

func TestRetryCounter(t *testing.T) {

	testCases := []struct {
		expectedURL     string
		expectedRetries int
	}{
		{
			expectedURL:     "https://awebsite.atld",
			expectedRetries: 0,
		},
		{
			expectedURL:     "https://awebsite.atld?retry_number=1",
			expectedRetries: 1,
		},
		{
			expectedURL:     "https://awebsite.atld?retry_number=2",
			expectedRetries: 2,
		},
		{
			expectedURL:     "https://awebsite.atld?retry_number=3",
			expectedRetries: 3,
		},
	}

	ctx := WithRetryCounter(context.Background())
	u, err := url.Parse("https://awebsite.atld")
	require.NoError(t, err)
	obs := NewNullObservability()
	req := &http.Request{
		URL: u,
	}

	for _, tc := range testCases {
		SetRetryInQueryString(ctx, req.URL)
		assert.Equal(t, tc.expectedURL, req.URL.String())
		CountHTTPResult(ctx, obs, "srv", "op", 0, errors.New("boom"))
		IncrementRetryCounter(ctx)
	}
}
