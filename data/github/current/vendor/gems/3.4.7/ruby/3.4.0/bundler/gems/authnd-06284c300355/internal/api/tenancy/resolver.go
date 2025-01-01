package tenancy

import (
	"context"
	"time"

	"github.com/github/authnd/internal/common/models"
	"github.com/patrickmn/go-cache"
)

type Resolver interface {
	GetTenantForSlug(ctx context.Context, slug string) (*TenantContext, error)
}

type BusinessLookup func(ctx context.Context, slug string) (*models.Business, error)

func NewResolver(lookup BusinessLookup) Resolver {
	return &resolver{
		businessLookup: lookup,
		tenantCache:    cache.New(6*time.Hour, 5*time.Minute),
	}
}

type resolver struct {
	businessLookup BusinessLookup
	// read-through cache for tenant data
	tenantCache *cache.Cache
}

func (r *resolver) GetTenantForSlug(ctx context.Context, slug string) (*TenantContext, error) {
	if tenant, ok := r.tenantCache.Get(slug); ok {
		return tenant.(*TenantContext), nil
	}

	business, err := r.businessLookup(ctx, slug)
	if err != nil {
		return nil, err
	}

	tenantContext := &TenantContext{
		ID:        int(business.ID),
		Shortcode: business.Shortcode,
	}
	r.tenantCache.Set(slug, tenantContext, cache.DefaultExpiration)

	return tenantContext, nil
}
