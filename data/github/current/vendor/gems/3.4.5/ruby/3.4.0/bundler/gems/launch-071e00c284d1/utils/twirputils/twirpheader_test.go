package twirputils

import (
	"context"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestContextWithTwirpHeader(t *testing.T) {
	testCases := []struct {
		name                string
		ctx                 context.Context
		key                 string
		value               string
		headerAlreadyExists bool
		expected            http.Header
		shouldErr           bool
	}{
		{
			name:  "add twirp header to context without existing twirp header",
			ctx:   context.Background(),
			key:   "My-Header",
			value: "MyValue",
			expected: http.Header{
				"My-Header": []string{"MyValue"},
			},
		},
		{
			name:                "add new header to existing twirp header",
			ctx:                 context.Background(),
			key:                 "My-Header",
			value:               "MyValue",
			headerAlreadyExists: true,
			expected: http.Header{
				"Existing-Header": []string{"ExistingValue"},
				"My-Header":       []string{"MyValue"},
			},
			shouldErr: false,
		},
		{
			name:                "overwrite existing twirp header",
			ctx:                 context.Background(),
			key:                 "Existing-Header",
			value:               "NewValue",
			headerAlreadyExists: true,
			expected: http.Header{
				"Existing-Header": []string{"NewValue"},
			},
			shouldErr: false,
		},
		{
			name:      "attempt to write reserved twirp header",
			ctx:       context.Background(),
			key:       "Twirp-Version",
			value:     "SomeVersion",
			shouldErr: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			r := require.New(t)

			ctx := tc.ctx

			if tc.headerAlreadyExists {
				var err error
				ctx, err = ContextWithTwirpHeader(ctx, "Existing-Header", "ExistingValue")
				r.NoError(err)
			}

			ctx, err := ContextWithTwirpHeader(ctx, tc.key, tc.value)
			if tc.shouldErr {
				r.Error(err)
				return
			}

			header, ok := twirp.HTTPRequestHeaders(ctx)
			if !ok {
				t.Error("expected twirp header to be set in context")
			}

			r.Equal(tc.expected, header)
		})
	}
}
