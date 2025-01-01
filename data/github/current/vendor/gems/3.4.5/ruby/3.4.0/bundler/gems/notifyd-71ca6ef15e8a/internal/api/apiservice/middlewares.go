package apiservice

import (
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

/*
tenantMiddleware extracts the tenant information from the request and updates the current tenant
with it in multi-tenant environments.
The Tenant is saved in the request's context. This is the only way to pass extra information to
specific servers. It's up to the servers to extract the Tenant from the context as early as possible
and pass it explicitly to other parts of the stack.
*/
type tenantMiddleware struct {
	logger log.Logger
	tenant tenancy.Tenant
}

func (t *tenantMiddleware) Handler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		tenant := t.tenant
		ctx := r.Context()

		if t.tenant.IsMultiTenant() {
			var err error
			tenant, err = tenancy.UpdateFromHeaders(tenant, r.Header)

			if err != nil {
				t.logger.WithContext(ctx).WithError(err).Info("Error extracting tenant information from headers")
			}

			fields := []kvp.Field{}
			if tenant.Slug() != "" {
				ctx = o11y.CtxSetTenantSlug(ctx, tenant.Slug())
				fields = append(fields, kvp.String("gh.tenant", tenant.Slug()))
			}

			if tenant.ID() != 0 {
				fields = append(fields, kvp.Int64("gh.tenant.id", tenant.ID()))
			}

			if len(fields) > 0 {
				t.logger.WithContext(ctx).Info("Found Tenant in incoming headers", fields...)
			}
		}

		r = r.WithContext(tenancy.ContextWithTenant(ctx, tenant))
		next.ServeHTTP(w, r)
	}

	return http.HandlerFunc(fn)
}
