package abuse

import (
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"regexp"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/utils/appcontext"
)

type StatusServicer struct {
	Log      logger.Logger
	Stats    statter.Statter
	Deployer deploy.LaunchDeploymentService
}

var _ mu.Servicer = (*StatusServicer)(nil)

const (
	abuseStatusRoute          = `/actions/abuse/status`
	abuseDetectionStatusRoute = `/actions/abuse-detection/status`
)

func NewServicer(log logger.Logger, stats statter.Statter, deployer deploy.LaunchDeploymentService) *StatusServicer {
	return &StatusServicer{
		Log:      log,
		Stats:    stats,
		Deployer: deployer,
	}
}

func (s *StatusServicer) Routes() []mu.Route {
	return []mu.Route{
		mu.Post(abuseStatusRoute, s.HandleAbuseStatus),
		mu.Post(abuseDetectionStatusRoute, s.HandleAbuseDetectionStatus),
	}
}

var signatureHeaderRegex = regexp.MustCompile(`(?i)HMAC-SHA512 Signature=([\S]+)`)

func (s *StatusServicer) HandleAbuseStatus(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPAbuseStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: abuseStatusRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "InvalidAbuseStatusRequest", nil, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	body, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusInternalServerError, errors.Wrap(err, "could not read http body"))
		return
	}
	defer req.Body.Close()

	asr := &deploy.AbuseStatusRequest{
		Status:     body,
		Signature:  getSignature(req),
		RequestURI: fmt.Sprintf("https://%s%s", req.Host, req.URL.RequestURI()),
	}

	res, err := s.Deployer.AbuseStatus(ctx, asr)

	if err != nil {
		respondWithError(http.StatusInternalServerError, errors.Wrap(err, "unable to update abuse status"))
		return
	}
	if !res.ValidSignature {
		respondWithError(http.StatusUnauthorized, errors.New("signature verification failed"))
		return
	}

	resp.WriteHeader(http.StatusOK)
}

func (s *StatusServicer) HandleAbuseDetectionStatus(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPAbuseStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: abuseDetectionStatusRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "InvalidAbuseDetectionStatusRequest", nil, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	body, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusInternalServerError, errors.Wrap(err, "could not read http body"))
		return
	}
	defer req.Body.Close()

	asr := &deploy.AbuseStatusRequest{
		Status:     body,
		Signature:  getSignature(req),
		RequestURI: fmt.Sprintf("https://%s%s", req.Host, req.URL.RequestURI()),
	}

	res, err := s.Deployer.AbuseDetectionStatus(ctx, asr)

	if err != nil {
		respondWithError(http.StatusInternalServerError, errors.Wrap(err, "unable to update abuse detection status"))
		return
	}
	if !res.ValidSignature {
		respondWithError(http.StatusUnauthorized, errors.New("signature verification failed"))
		return
	}

	resp.WriteHeader(http.StatusOK)
}

func getSignature(req *http.Request) []byte {
	matches := signatureHeaderRegex.FindStringSubmatch(req.Header.Get("Authorization"))
	if len(matches) < 2 {
		return nil
	}

	signature, err := base64.StdEncoding.DecodeString(matches[1])
	if err != nil {
		return nil
	}

	return signature
}

func (s *StatusServicer) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}
