package globalid

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/go-kvp"
	"github.com/go-chi/chi"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	errutil "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/appcontext"

	"github.com/github/launch/pkg/mu"

	"github.com/pkg/errors"
)

type Service struct {
	obs           *observability.Observability
	ghTwirpClient ghtwirp.Client
	verifier      *hmac.HTTPVerifier
}

// NewService returns a Service
func NewService(
	obs *observability.Observability,
	ghTwirpClient ghtwirp.Client,
	verifier *hmac.HTTPVerifier,
) *Service {
	return &Service{
		obs:           obs,
		ghTwirpClient: ghTwirpClient,
		verifier:      verifier,
	}
}

type SingleResponse struct {
	GlobalID string `json:"nextGlobalId"`
}

type BulkRequest struct {
	GlobalIDs []string `json:"globalIds"`
}

type BulkResponse struct {
	NextGlobalIDMap map[string]types.GlobalID `json:"nextGlobalIdMap"`
	AllIDsFound     bool                      `json:"allIdsFound"`
}

var _ mu.Servicer = (*Service)(nil)

const (
	getBulkNextGlobalIDsCallbackRoute = `/actions/nextglobalids`
	getNextGlobalIDCallbackRoute      = `/actions/nextglobalid/{escaped_legacy_id}`
	// should accomodate roughly 100k legacy global ids
	maxHTTPRead = 4 * 1024 * 1024
)

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		// All routes authenticated via a base64 encoded signature passed as a HTTP header.
		mu.Get(getNextGlobalIDCallbackRoute, s.GetNextGlobalID),
		// A post is used to send the list of global ids in the body
		mu.Post(getBulkNextGlobalIDsCallbackRoute, s.GetBulkNextGlobalIDs),
	}
}

func (s *Service) GetNextGlobalID(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.NextGlobalIDLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: getNextGlobalIDCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	// The GET request shouldn't include a body at all, but we'll read it in case a legitimate client sent it.
	body, err := io.ReadAll(io.LimitReader(req.Body, maxHTTPRead))
	if err != nil {
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}
	if len(body) >= maxHTTPRead {
		s.respondWithError(ctx, http.StatusRequestEntityTooLarge, err, resp)
		return
	}

	gblidEscaped := chi.URLParam(req, "escaped_legacy_id")

	gblid, err := url.QueryUnescape(gblidEscaped)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get unescaped globalID"), resp)
		return
	}

	if err := s.verifier.Verify(ctx, req, body); err != nil {
		err := errors.Wrap(err, "HMAC verification failed")
		s.respondWithError(ctx, http.StatusForbidden, err, resp)
		return
	}

	nextGlobalID, err := s.ghTwirpClient.GetNextGlobalID(ctx, gblid)
	if err != nil {
		if errutil.IsNotFoundError(err) {
			ctx = ctxstash.WithFields(ctx,
				kvp.String("gh.launch.global_id.request_failed_reason", "globalID not found"))
			s.respondWithError(ctx, http.StatusNotFound, err, resp)
		} else {
			s.respondWithError(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get next global id"), resp)
		}
		return
	}

	svcResponse := SingleResponse{
		GlobalID: nextGlobalID.String(),
	}

	resp.Header().Set("Content-Type", "application/json")
	resp.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(resp).Encode(&svcResponse); err != nil {
		err := errors.Wrap(err, "failed to encode globalID response")
		s.obs.Logger.Report(ctx, err)
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}
}

func (s *Service) GetBulkNextGlobalIDs(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.NextGlobalIDLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: getBulkNextGlobalIDsCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	start := time.Now()
	body, err := io.ReadAll(io.LimitReader(req.Body, maxHTTPRead))
	if err != nil {
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}
	if len(body) >= maxHTTPRead {
		s.respondWithError(ctx, http.StatusRequestEntityTooLarge, err, resp)
		return
	}

	if err := s.verifier.Verify(ctx, req, body); err != nil {
		err := errors.Wrap(err, "HMAC verification failed")
		s.respondWithError(ctx, http.StatusForbidden, err, resp)
		return
	}

	var ngidr *BulkRequest
	if err := json.Unmarshal(body, &ngidr); err != nil {
		err := errors.Wrap(err, "error unmarshalling request body")
		s.obs.Logger.Report(ctx, err)
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	nextGlobalIDMap, allIDsFound, err := s.ghTwirpClient.GetNextGlobalIDs(ctx, ngidr.GlobalIDs)
	if err != nil {
		s.obs.Logger.Error(ctx, "could not get next global ids",
			kvp.Err(err),
			kvp.Int("gh.launch.global_id.num_ids_in_request", len(ngidr.GlobalIDs)),
			kvp.String("gh.launch.global_id.ids_in_request", strings.Join(ngidr.GlobalIDs, ",")))

		s.respondWithError(ctx, http.StatusInternalServerError, errors.Wrap(err, "could not get next global ids"), resp)
		return
	}

	s.obs.Logger.Debug(ctx, "GetNextGlobalIDs response",
		kvp.Int("gh.launch.global_id.num_ids_in_request", len(ngidr.GlobalIDs)),
		kvp.Int("gh.launch.global_id.num_next_ids_in_response", len(nextGlobalIDMap)),
		kvp.Bool("gh.launch.global_id.found_all_ids", allIDsFound),
		kvp.Duration("gh.launch.global_id.request_elapsed_seconds", time.Since(start))) //nolint:staticcheck

	svcResponse := BulkResponse{
		NextGlobalIDMap: nextGlobalIDMap,
		AllIDsFound:     allIDsFound,
	}

	resp.Header().Set("Content-Type", "application/json")
	resp.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(resp).Encode(&svcResponse); err != nil {
		err := errors.Wrap(err, "failed to encode globalID response")
		s.obs.Logger.Report(ctx, err)
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}
}

// ServiceContext applied to every request
func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Service) respondWithError(ctx context.Context, code int, err error, resp http.ResponseWriter) { //nolint:staticcheck
	ctx, span := tracing.Start(ctx)
	defer span.End()

	s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
	s.obs.Counter(ctx, "InvalidGetNextGlobalIDRequest", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
	span.RecordError(err)
	http.Error(resp, http.StatusText(code), code)
}
