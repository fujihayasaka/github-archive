// Package proxima provides utilities for working with the Proxima API.
package proxima

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/sweagentd/internal/requestctx"
)

// ReplaceTenantPlaceholder replaces <tenant> placeholder (or escaped) in URLs with the actual tenant slug from context
// make sure this stays in sync with the github client
func ReplaceTenantPlaceholder(ctx context.Context, urlStr string) (string, error) {
	tenantSlug := requestctx.TenantSlug(ctx)
	var tenantReplacementString string
	containsTenantPlaceholder := strings.Contains(urlStr, "<tenant>")
	containsEncodedTenantPlaceholder := strings.Contains(urlStr, "%3Ctenant%3E")

	if containsTenantPlaceholder {
		tenantReplacementString = "<tenant>"
	} else if containsEncodedTenantPlaceholder {
		tenantReplacementString = "%3Ctenant%3E"
	}

	if containsTenantPlaceholder || containsEncodedTenantPlaceholder {
		if tenantSlug == "" {
			return "", fmt.Errorf("%s is expected to be filled but no tenant slug can be found", tenantReplacementString)
		} else {
			return strings.ReplaceAll(urlStr, tenantReplacementString, tenantSlug), nil
		}
	}

	return urlStr, nil
}
