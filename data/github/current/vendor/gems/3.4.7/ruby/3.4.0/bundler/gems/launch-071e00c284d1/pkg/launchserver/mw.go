package launchserver

import (
	"fmt"
	"net/http"
	"runtime/debug"
	"strconv"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu/muhttp/mw"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/ghtenant"
)

type CtxStashConfig struct {
	Name         string
	BuildVersion string
	Host         string
	StatsTags    stats.Tags
}

func SetupCtxStashMiddleware(cfg *CtxStashConfig) func(h http.Handler) http.Handler {
	return func(h http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ctx := ctxstash.WithTags(r.Context(), cfg.StatsTags)

			fields := make(map[string]string) // Includes launch_service, launch_env, release, deployed_to from GetApplicationMetadata
			for k, v := range cfg.StatsTags {
				fields[k] = v
			}
			fields["app"] = cfg.Name
			fields["sha"] = cfg.BuildVersion
			fields["host"] = cfg.Host

			ctx = ctxstash.WithFields(ctx, appcontext.MapToLogFields(fields)...)
			ctx = ctxstash.WithReqID(ctx, mw.GetGitHubRequestID(ctx))

			vssID := r.Header.Get(azpcorrelation.VSSE2EIDHeaderName)
			if vssID != "" {
				ctx = ctxstash.WithVSSRequestID(ctx, vssID)
				ctx = azpcorrelation.WithVSSID(ctx, vssID)
				w.Header().Set(azpcorrelation.VSSE2EIDHeaderName, vssID)
			}

			orchID := r.Header.Get("X-GitHub-Actions-Orchestration-Id")
			if orchID != "" {
				ctx = ctxstash.WithVSSOrchestrationID(ctx, orchID)
			}

			h.ServeHTTP(w, r.WithContext(ctx))
		}
		return http.HandlerFunc(fn)
	}
}

func RecoverPanics(obs *observability.Observability) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rvr := recover(); rvr != nil {
					var err error
					if e, ok := rvr.(error); ok {
						err = e
					} else {
						err = fmt.Errorf("%v", rvr)
					}

					obs.Report(r.Context(), errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
					http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
				}
			}()
			next.ServeHTTP(w, r)
		}
		return http.HandlerFunc(fn)
	}
}

func SetupGitHubTenantMiddleware(isMultiTenant bool, obs *observability.Observability) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			if !isMultiTenant {
				next.ServeHTTP(w, r)
				return
			}

			tenantIDs := r.Header.Values(ghtenant.GitHubTenantIDHeader)

			// Some clients such as actions-dotnet do not propagate tenant contexts
			if len(tenantIDs) == 0 {
				next.ServeHTTP(w, r)
				return
			}

			if len(tenantIDs) > 1 {
				w.WriteHeader(http.StatusBadRequest)
				err := fmt.Errorf("'%s' header should not have multiple tenant ids", ghtenant.GitHubTenantIDHeader)
				obs.Report(r.Context(), errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			}

			tenantID, err := strconv.ParseInt(tenantIDs[0], 10, 64)
			if err != nil {
				err := fmt.Errorf("'%s' header val '%s' is not parsable to int64", tenantIDs[0], ghtenant.GitHubTenantIDHeader)
				obs.Report(r.Context(), err)
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			}

			// context is immutable, so we need to create a new context with the tenant id and slug
			ctx, err := ghtenant.ContextWithTenantID(r.Context(), tenantID, isMultiTenant)
			if err != nil {
				err := fmt.Errorf("error adding tenantID to context: %w", err)
				obs.Report(r.Context(), err)
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			}

			tenantSlugs := r.Header.Values(ghtenant.GitHubTenantHeader)

			if len(tenantSlugs) == 0 {
				next.ServeHTTP(w, r.WithContext(ctx))
				return
			}

			if len(tenantSlugs) > 1 {
				w.WriteHeader(http.StatusBadRequest)
				err := fmt.Errorf("'%s' header should not have multiple tenant slugs", ghtenant.GitHubTenantHeader)
				obs.Report(r.Context(), errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			}

			ctx, err = ghtenant.ContextWithTenantSlug(ctx, tenantSlugs[0], isMultiTenant)
			if err != nil {
				err := fmt.Errorf("error adding tenant slug to context: %w", err)
				obs.Report(r.Context(), err)
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			}

			next.ServeHTTP(w, r.WithContext(ctx))
		}

		return http.HandlerFunc(fn)
	}
}
