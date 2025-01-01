package tenancy

import (
	"context"
	"net/http"
	"strconv"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/twitchtv/twirp"
)

const (
	TENANT_SLUG_HEADER      = "X-GitHub-Tenant"
	TENANT_ID_HEADER        = "X-GitHub-Tenant-ID"
	TENANT_SHORTCODE_HEADER = "X-GitHub-Tenant-Shortcode"
)

type TenantContextKey struct{}

type TenantContext struct {
	ID        int
	Shortcode string
}

func GetTenantContext(ctx context.Context) *TenantContext {
	v := ctx.Value(TenantContextKey{})
	if v == nil {
		return nil
	}
	return v.(*TenantContext)
}

// adds a TenantContext value to a context, so that downstream calls can be aware of the tenant
func ApplyTenantContext(ctx context.Context, resolver Resolver, req *http.Request) (context.Context, error) {
	diagnostics.Logger(ctx).Debug("applying tenant context")

	// adds tenant to context and logger fields
	newCtx := func(ctx context.Context, tc *TenantContext) (context.Context, error) {
		ctx = diagnostics.WithLoggerFields(ctx,
			kvp.String("gh.tenant.id", strconv.Itoa(tc.ID)),
			kvp.String("gh.tenant.shortcode", tc.Shortcode))
		diagnostics.Logger(ctx).Info("successfully resolved tenant for request")

		return context.WithValue(ctx, TenantContextKey{}, tc), nil
	}

	tenant, err := tenantFromHeaders(req.Header)
	if err == nil {
		// both tenant ID and Shortcode headers required headers are present
		return newCtx(ctx, tenant)
	}

	tenant_slug := req.Header.Get(TENANT_SLUG_HEADER)
	if tenant_slug == "" {
		return nil, twirp.NewErrorf(twirp.Malformed, "missing tenancy headers: either %s or both %s and %s are required",
			TENANT_SLUG_HEADER, TENANT_ID_HEADER, TENANT_SHORTCODE_HEADER,
		)
	}
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.tenant.slug", tenant_slug))
	diagnostics.Logger(ctx).Info("resolving tenant context from slug")

	// attempt to resolve tenant from slug via the businesses table
	tenant, err = resolver.GetTenantForSlug(ctx, tenant_slug)
	if err != nil {
		return nil, twirp.NewErrorf(twirp.Internal, "failed to resolve tenant from slug (%s): %w", tenant_slug, err)
	}

	return newCtx(ctx, tenant)
}

func tenantFromHeaders(headers http.Header) (*TenantContext, error) {
	tenant_id, err := strconv.Atoi(headers.Get(TENANT_ID_HEADER))
	if err != nil {
		return nil, twirp.NewErrorf(twirp.Malformed, "missing %s header", TENANT_ID_HEADER)
	}

	tenant_shortcode := headers.Get(TENANT_SHORTCODE_HEADER)
	if tenant_shortcode == "" {
		return nil, twirp.NewErrorf(twirp.Malformed, "missing %s header", TENANT_SHORTCODE_HEADER)
	}

	return &TenantContext{
		ID:        tenant_id,
		Shortcode: tenant_shortcode,
	}, nil
}
