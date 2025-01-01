// Package tenant provides an HTTP handler wrapper ("middleware") that
// stows the GitHub tenant identifier in a Context to make it easy to plumb it through
// a service from the incoming request to an outgoing one.
//
// Tenant context is established by the ingress request handler and propagated across
// service boundaries.
package tenant

import (
	"context"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/headers"
)

const (
	// TenantKey is the context key for the X-GitHub-Tenant slug value.
	ctxTenantKey = "go-http-Tenant"
	// TenantIDKey is the context key for the X-GitHub-Tenant-ID value.
	ctxTenantIDKey = "go-http-Tenant-ID"
)

// Tenant is a middleware that handles the github tenant.
type Tenant struct {
	// A logger to use for logging. Use nil to get a default logger named tenant. Use a
	// log.NewNullLogger() to suppress logging.
	Logger log.Logger
}

// Handler is a middleware that handles identifying and setting the tenant slug and tenantID context.
func (t *Tenant) Handler(next http.Handler) http.Handler {
	if t.Logger == nil {
		t.Logger = log.Named("tenant")
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := t.Logger.WithContext(r.Context())

		tenant := r.Header.Get(headers.Tenant)
		if tenant == "" {
			l.Debug("missing GitHub tenant header")
		}

		tenantID := r.Header.Get(headers.TenantID)
		if tenantID == "" {
			l.Debug("missing GitHub tenant ID header")
		}

		ctx := r.Context()
		if tenant != "" {
			ctx = TenantContext(ctx, tenant)
		}
		if tenantID != "" {
			ctx = TenantIDContext(ctx, tenantID)
		}

		r = r.WithContext(ctx)
		next.ServeHTTP(w, r)
	})
}

// GetTenant returns the GitHub tenant slug identifier if one is present.
func GetTenant(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if tenant, ok := ctx.Value(ctxTenantKey).(string); ok {
		return tenant
	}
	return ""
}

// GetTenantID returns the GitHub tenant ID identifier if one is present.
func GetTenantID(ctx context.Context) string {
	if ctx == nil {
		return ""
	}

	if tenantID, ok := ctx.Value(ctxTenantIDKey).(string); ok {
		return tenantID
	}
	return ""
}

// GetTenantField returns a kvp field intended for consistent GitHub tenant slug identity logging.
func GetTenantField(ctx context.Context) kvp.Field {
	tenant := GetTenant(ctx)
	return kvp.String("gh.tenant", tenant)
}

// GetTenantIDField returns a kvp field intended for consistent GitHub tenant ID identity logging.
func GetTenantIDField(ctx context.Context) kvp.Field {
	tenantID := GetTenantID(ctx)
	return kvp.String("gh.tenant.id", tenantID)
}

// TenantContext creates a new context based on the supplied parent, with the Tenant
// set to the specified value. If a Tenant already exists, it will be overwritten.
//
//nolint:revive // not renaming to avoid breaking changes
func TenantContext(ctx context.Context, id string) context.Context {
	//nolint:staticcheck,revive // SA1029 should be ignored, context collisions are acceptable across major versions
	return context.WithValue(ctx, ctxTenantKey, id)
}

// TenantIDContext creates a new context based on the supplied parent, with the Tenant ID
// set to the specified value. If a Tenant ID already exists, it will be overwritten.
//
//nolint:revive // not renaming to avoid breaking changes
func TenantIDContext(ctx context.Context, id string) context.Context {
	//nolint:staticcheck,revive // SA1029 should be ignored, context collisions are acceptable across major versions
	return context.WithValue(ctx, ctxTenantIDKey, id)
}

// Forward is a request hook that looks for X-GitHub-Tenant or X-GitHub-Tenant-ID in the incoming context and adds them to r's headers.
func Forward(r *http.Request) {
	ctx := r.Context()

	if tenant := GetTenant(ctx); tenant != "" {
		r.Header.Set(headers.Tenant, tenant)
	}

	if tenantID := GetTenantID(ctx); tenantID != "" {
		r.Header.Set(headers.TenantID, tenantID)
	}
}
