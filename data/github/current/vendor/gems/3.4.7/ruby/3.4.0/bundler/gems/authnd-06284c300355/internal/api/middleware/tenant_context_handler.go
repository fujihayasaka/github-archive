package middleware

import (
	"net/http"
	"strings"

	tenancy "github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/justinas/alice"
)

func TenantContextHandler(isProxima bool, resolver tenancy.Resolver) alice.Constructor {
	return func(base http.Handler) http.Handler {
		return http.HandlerFunc(func(wr http.ResponseWriter, req *http.Request) {
			// don't worry about tenancy in non-Proxima envs
			if !isProxima {
				base.ServeHTTP(wr, req)
				return
			}

			// only require tenancy for twirp requests, e.g. bypass for /_ping, chatops, etc.
			if !strings.HasPrefix(req.URL.Path, "/twirp/") {
				base.ServeHTTP(wr, req)
				return
			}

			logger := diagnostics.Logger(req.Context())
			if ctx, err := tenancy.ApplyTenantContext(req.Context(), resolver, req); err == nil {
				logger.Info("successfully applied tenant context")
				req = req.WithContext(ctx)
				base.ServeHTTP(wr, req)
			} else {
				logger.WithError(err).Warn("error applying tenant context")
				http.Error(wr, err.Error(), http.StatusBadRequest)
			}
		})
	}
}
