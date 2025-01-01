package cache

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/appcontext"
)

type Service struct {
	obs      *observability.Observability
	hydro    events.Hydro
	verifier *hmac.HTTPVerifier
	db       deployer.AzpResourcesLoader
}

// NewService returns an instance of cache service
func NewService(
	obs *observability.Observability,
	hydro events.Hydro,
	verifier *hmac.HTTPVerifier,
	db deployer.AzpResourcesLoader,
) *Service {
	return &Service{
		obs:      obs,
		hydro:    hydro,
		verifier: verifier,
		db:       db,
	}
}

var _ mu.Servicer = (*Service)(nil)

const (
	updateCacheUsageCallbackRoute = `/actions/cache/usage`
	maxHTTPRead                   = 4096
)

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		// Authenticated via a base64 encoded signature passed as a HTTP header.
		mu.Patch(updateCacheUsageCallbackRoute, s.UpdateCacheUsage),
	}
}

func (s *Service) UpdateCacheUsage(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()
	start := time.Now()

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: updateCacheUsageCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	body, err := io.ReadAll(io.LimitReader(req.Body, maxHTTPRead))
	if err == nil && len(body) == 0 {
		err = errors.New("empty payload")
	}
	if err != nil {
		s.respondWithStatus(ctx, http.StatusBadRequest, err, start, resp)
		return
	}
	if len(body) >= maxHTTPRead {
		s.respondWithStatus(ctx, http.StatusRequestEntityTooLarge, err, start, resp)
		return
	}

	if err := s.verifier.Verify(ctx, req, body); err != nil {
		err := errors.Wrap(err, "HMAC verification failed")
		s.respondWithStatus(ctx, http.StatusForbidden, err, start, resp)
		return
	}
	cacheUsageMessage, err := s.getCacheUsageFromJSONPayload(ctx, body)
	if err != nil {
		err := errors.Wrap(err, "looking up cache usage")
		s.respondWithStatus(ctx, http.StatusBadRequest, err, start, resp)
		return
	}
	cacheUsageHydroEvent := events.NewHydroEvent(events.CacheUsageEvent, cacheUsageMessage)
	s.hydro.Emit(cacheUsageHydroEvent)
	s.respondWithStatus(ctx, http.StatusAccepted, nil, start, resp)
}

// ServiceContext applied to every request
func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Service) respondWithStatus(ctx context.Context, code int, err error, start time.Time, resp http.ResponseWriter) { //nolint:staticcheck
	tags := statter.Tags{"status_code": fmt.Sprintf("%d", code)}
	if err != nil {
		tags["error"] = "true"
		s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		http.Error(resp, http.StatusText(code), code)
	} else {
		tags["error"] = "false"
		resp.WriteHeader(code)
	}
	s.obs.Timing(ctx, "receiver.cache_usage_callback_duration", tags, time.Since(start))
	s.obs.Counter(ctx, "receiver.update_cache_status", tags, 1)
}
