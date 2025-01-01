package status

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	"github.com/go-chi/chi"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/auth/hkdf"
	deployer "github.com/github/launch/services/deploy/status"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/receiver"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/stringutils"
)

const maxBodySize = 4 * 1 << 20 // 4 MiB

type Servicer struct {
	Log           logger.Logger
	Stats         statter.Statter
	Verifier      hkdf.Verifier
	Deployer      deployer.LaunchStatusService
	IsLab         bool
	IsDevelopment bool
	ReceiverURL   string
	GHTwirpClient ghtwirp.Client
}

var _ mu.Servicer = (*Servicer)(nil)

const (
	jobStatusCallbackRoute  = `/actions/build/{workflowID:[0-9A-Za-z-]+}/jobs/{jobID}`
	runStatusCallbackRoute  = `/actions/build/{workflowID:[0-9A-Za-z-]+}`
	gateStatusCallbackRoute = `/actions/build/{workflowID:[0-9A-Za-z-]+}/gates/{gateID}`
)

func (s *Servicer) Routes() []mu.Route {
	return []mu.Route{
		// Authenticated via a base64 encoded signature passed as a HTTP header.
		mu.Patch(jobStatusCallbackRoute, s.HandleJobStatus),
		mu.Patch(runStatusCallbackRoute, s.HandleRunStatus),
		mu.Patch(gateStatusCallbackRoute, s.HandleGateStatus),
	}
}

func (s *Servicer) HandleJobStatus(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPJobStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: jobStatusCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	wfid := WorkflowID(chi.URLParam(req, "workflowID"))
	jid := JobID(chi.URLParam(req, "jobID"))

	span.SetAttributes(
		attribute.String("gh.actions.plan_id", string(wfid)),
		attribute.String("gh.launch.job.id", string(jid)),
	)

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.actions.plan_id", string(wfid)),
		kvp.String("gh.launch.job.id", string(jid)),
	)

	if s.IsLab || s.IsDevelopment {
		reqStr, err := stringutils.HTTPRequestToString(req)
		if err == nil {
			s.Log.Log(ctx, "debugging job status postback request", kvp.Any("gh.launch.job_status.request", reqStr))
		}
	}

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "receiver.job_status", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, code, err := readBody(req)
	if err != nil {
		respondWithError(code, err)
		return
	}

	isValid, err := receiver.VerifySignature(s.Verifier, req, data, s.ReceiverURL)
	if err != nil {
		respondWithError(http.StatusBadRequest, err)
		return
	}
	if !isValid {
		respondWithError(http.StatusUnauthorized, errors.New("Signature verification failed"))
		return
	}

	// We only want to check for the postbacks being disabled inside of our lab
	// environment for testing purposes.
	if s.arePostbacksDisabled(ctx) {
		respondWithError(http.StatusTooManyRequests, errors.New("status postbacks disabled"))
		return
	}

	status, err := s.getJobStatusUpdateFromJSONPayload(ctx, wfid, jid, data)
	if err != nil {
		err := errors.Wrap(err, "unparsable StatusUpdate request")
		s.Log.Report(ctx, err)
		respondWithError(http.StatusBadRequest, err)
		return
	}

	_, err = s.Deployer.JobStatus(ctx, status)
	if status, _, ok := svcerr.ExtractHTTPError(err); ok {
		// we've already reported this error in the deployer
		respondWithError(status, err)
		return
	}
	if err != nil {
		err := errors.Wrap(err, "Status RPC call to deployer failed")
		if svcerr.CallerShouldReportError(err) {
			s.Log.Report(ctx, err)
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	s.Stats.Counter(ctx, "receiver.job_status", statter.Tags{"status_code": "200"}, 1)
	resp.WriteHeader(http.StatusOK)
}

func readBody(req *http.Request) (data []byte, code int, err error) {
	if req.ContentLength > int64(maxBodySize) {
		return nil, http.StatusRequestEntityTooLarge, errors.Errorf("content length too large, max is %d", maxBodySize)
	}
	// read 1 byte beyond the max size, so we can assert if it's too large
	data, err = io.ReadAll(io.LimitReader(req.Body, maxBodySize+1))
	if err != nil {
		return nil, http.StatusInternalServerError, errors.Wrap(err, "could not read http body")
	}
	if len(data) > maxBodySize {
		return nil, http.StatusRequestEntityTooLarge, errors.Errorf("request body too large, max is %d", maxBodySize)
	}
	return data, http.StatusOK, nil
}

func (s *Servicer) HandleRunStatus(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPRunStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: runStatusCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	wfid := WorkflowID(chi.URLParam(req, "workflowID"))

	span.SetAttributes(
		attribute.String("gh.actions.plan_id", string(wfid)),
	)

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.actions.plan_id", string(wfid)),
	)
	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "receiver.run_status", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("status", code))
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, code, err := readBody(req)
	if err != nil {
		respondWithError(code, err)
		return
	}

	if postbackAge, err := s.getPostbackAge(req); err == nil {
		ctx = ctxstash.WithFields(ctx,
			kvp.Int64("gh.launch.run_status.postback_age_sec", int64(postbackAge.Seconds())),
		)
	}

	isValid, err := receiver.VerifySignature(s.Verifier, req, data, s.ReceiverURL)
	if err != nil {
		respondWithError(http.StatusBadRequest, err)
		return
	}
	if !isValid {
		s.Log.Debug(ctx, "signature verification failed for workflow", kvp.String("gh.actions.plan_id", string(wfid)))
		respondWithError(http.StatusUnauthorized, errors.New("Signature verification failed"))
		return
	}

	if s.arePostbacksDisabled(ctx) {
		respondWithError(http.StatusTooManyRequests, errors.New("status postbacks disabled"))
		return
	}

	if s.IsLab || s.IsDevelopment {
		reqStr, err := stringutils.HTTPRequestToString(req)
		if err == nil {
			s.Log.Log(ctx, "debugging run status postback request", kvp.Any("gh.launch.job_status.request", reqStr))
		}
	}

	status, err := s.getRunStatusUpdateFromJSONPayload(ctx, wfid, data)
	if err != nil {
		err := errors.Wrap(err, "unparsable StatusUpdate request")
		s.Log.Report(ctx, err)
		respondWithError(http.StatusBadRequest, err)
		return
	}

	_, err = s.Deployer.RunStatus(ctx, status)
	if status, _, ok := svcerr.ExtractHTTPError(err); ok {
		// we've already reported this error in the deployer
		respondWithError(status, err)
		return
	}
	if err != nil {
		err := errors.Wrap(err, "Status RPC call to deployer failed")
		if svcerr.CallerShouldReportError(err) {
			s.Log.Report(ctx, err)
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	s.Stats.Counter(ctx, "receiver.run_status", statter.Tags{"status_code": "200"}, 1)
	resp.WriteHeader(http.StatusOK)
}

func (s *Servicer) HandleGateStatus(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPGateStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: runStatusCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	wfid := WorkflowID(chi.URLParam(req, "workflowID"))
	gaid := GateID(chi.URLParam(req, "gateID"))

	span.SetAttributes(
		attribute.String("gh.actions.plan_id", string(wfid)),
		attribute.String("gh.launch.gate.id", string(gaid)),
	)

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.gate.id", string(gaid)),
	)

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "receiver.gate_status", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, code, err := readBody(req)
	if err != nil {
		respondWithError(code, err)
		return
	}

	if postbackAge, err := s.getPostbackAge(req); err == nil {
		ctx = ctxstash.WithFields(ctx,
			kvp.Int64("gh.launch.run_status.postback_age_sec", int64(postbackAge.Seconds())),
		)
	}

	isValid, err := receiver.VerifySignature(s.Verifier, req, data, s.ReceiverURL)
	if err != nil {
		respondWithError(http.StatusBadRequest, err)
		return
	}
	if !isValid {
		s.Log.Debug(ctx, "signature verification failed for gate update", kvp.String("gh.launch.gate.id", string(gaid)))
		respondWithError(http.StatusUnauthorized, errors.New("Signature verification failed"))
		return
	}

	if s.arePostbacksDisabled(ctx) {
		respondWithError(http.StatusTooManyRequests, errors.New("gate status postbacks disabled"))
		return
	}

	if s.IsLab {
		reqStr, err := stringutils.HTTPRequestToString(req)
		if err == nil {
			s.Log.Log(ctx, "debugging gate status postback request", kvp.Any("gh.launch.job_status.request", reqStr))
		}
	}

	status, err := s.getGateStatusUpdateFromJSONPayload(ctx, wfid, gaid, data)
	if err != nil {
		err := errors.Wrap(err, "unparsable StatusUpdate request")
		s.Log.Report(ctx, err)
		respondWithError(http.StatusBadRequest, err)
		return
	}

	_, err = s.Deployer.GateStatus(ctx, status)
	if status, _, ok := svcerr.ExtractHTTPError(err); ok {
		// we've already reported this error in the deployer
		respondWithError(status, err)
		return
	}
	if err != nil {
		err := errors.Wrap(err, "Status RPC call to deployer failed")
		if svcerr.CallerShouldReportError(err) {
			s.Log.Report(ctx, err)
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	s.Stats.Counter(ctx, "receiver.gate_status", statter.Tags{"status_code": "200"}, 1)
	resp.WriteHeader(http.StatusOK)
}

func (s *Servicer) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Servicer) getPostbackAge(req *http.Request) (time.Duration, error) {
	ts, err := receiver.GetTimestampFromRequest(req)
	if err != nil {
		return 0, err
	}
	return time.Since(ts), nil
}

func (s *Servicer) arePostbacksDisabled(ctx context.Context) bool {
	arePostbacksDisabled := s.GHTwirpClient.IsFeatureEnabledGlobally(ctx, github.DisableStatusPostbacksFeatureFlag)
	if arePostbacksDisabled {
		s.Log.Debug(ctx, "status postbacks are currently disabled, returning 429")
		return true
	}

	return false
}
