package proxima

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReplaceTenantPlaceholder(t *testing.T) {
	tests := []struct {
		name          string
		urlStr        string
		tenantSlug    string
		expected      string
		expectedError bool
	}{
		{
			name:       "URL with tenant placeholder",
			urlStr:     "https://api.github.com/<tenant>/twirp/service",
			tenantSlug: "test-tenant-123",
			expected:   "https://api.github.com/test-tenant-123/twirp/service",
		},
		{
			name:       "URL with multiple tenant placeholders",
			urlStr:     "https://api.github.com/<tenant>/twirp/<tenant>/service",
			tenantSlug: "test-tenant-123",
			expected:   "https://api.github.com/test-tenant-123/twirp/test-tenant-123/service",
		},
		{
			name:       "URL with URL-encoded tenant placeholder",
			urlStr:     "https://api.github.com/%3Ctenant%3E/twirp/service",
			tenantSlug: "test-tenant-123",
			expected:   "https://api.github.com/test-tenant-123/twirp/service",
		},
		{
			name:       "URL without tenant placeholder",
			urlStr:     "https://api.github.com/twirp/service",
			tenantSlug: "test-tenant-123",
			expected:   "https://api.github.com/twirp/service",
		},
		{
			name:          "URL with tenant placeholder but no tenant ID in context",
			urlStr:        "https://api.github.com/<tenant>/twirp/service",
			tenantSlug:    "",
			expected:      "",
			expectedError: true,
		},
		{
			name:          "URL with URL-encoded tenant placeholder but no tenant ID in context",
			urlStr:        "https://api.github.com/%3Ctenant%3E/twirp/service",
			tenantSlug:    "",
			expected:      "",
			expectedError: true,
		},
		{
			name:       "Empty URL",
			urlStr:     "",
			tenantSlug: "test-tenant-123",
			expected:   "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{
					TenantSlug: tt.tenantSlug,
				})
			}
			result, err := ReplaceTenantPlaceholder(ctx, tt.urlStr)
			if tt.expectedError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
