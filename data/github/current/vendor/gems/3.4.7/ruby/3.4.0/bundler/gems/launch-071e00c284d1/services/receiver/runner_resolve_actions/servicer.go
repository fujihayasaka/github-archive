package runnerresolveactions

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/github/go-kvp"
	"github.com/go-chi/chi"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	tokenauth "github.com/github/launch/services/auth/token"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pb/deploy"
	resolveactions "github.com/github/launch/services/receiver/resolve_actions"
	terrs "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/stringutils"
)

type Servicer struct {
	Obs           *observability.Observability
	AuthClient    tokenauth.Verifier
	IsLab         bool
	Deployer      deploy.LaunchDeploymentService
	GHTwirpClient ghtwirp.Client
}

var _ mu.Servicer = (*Servicer)(nil)

const (
	resolveCallbackRoute = `/actions/build/{workflowID:[0-9A-Za-z-]+}/jobs/{jobID}/runnerresolve/actions`
)

func (s *Servicer) Routes() []mu.Route {
	return []mu.Route{
		mu.Post(resolveCallbackRoute, s.HandleRunnerResolveActions),
	}
}

func (s *Servicer) HandleRunnerResolveActions(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPJobStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	respondWithError := func(code int, err error) {
		s.Obs.Counter(ctx, "receiver.runner_resolve_actions", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
		s.Obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: resolveCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	wfid := chi.URLParam(req, "workflowID")
	jid := chi.URLParam(req, "jobID")

	if !s.AuthClient.LaunchReceiverScopesValid(ctx, wfid, jid) {
		respondWithError(http.StatusUnauthorized, errors.New("Scope validation failed"))
		return
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.actions.plan_id", wfid),
		kvp.String("gh.launch.job.id", jid),
	)

	if s.IsLab {
		reqStr, err := stringutils.HTTPRequestToString(req)
		if err == nil {
			s.Obs.Log(ctx, "debugging resolve actions postback request", kvp.Any("gh.launch.resolve_actions.request", reqStr))
		}
	}

	data, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusBadRequest, errors.Wrap(err, "could not read http body"))
		return
	}

	var svcRequest resolveactions.ServiceRequest
	if err := json.Unmarshal(data, &svcRequest); err != nil {
		respondWithError(http.StatusUnprocessableEntity, errors.Wrap(err, "invalid request payload"))
		return
	}

	svcRequest.IsHostedRunner = s.AuthClient.GetRunnerTypeClaim(ctx) == tokenauth.RunnerTypeHosted

	svcResponse, err := resolveactions.ResolveActions(ctx, s.Deployer, wfid, jid, svcRequest)
	if status, _, ok := svcerr.ExtractHTTPError(err); ok {
		respondWithError(status, err)
		return
	}
	if err != nil {
		if terrs.IsRateLimitError(err) {
			err := errors.Wrap(err, "Launch rate limited while resolving actions")
			// Can be any error response as long as Actions Service knows how to handle it
			// This should really be a 500 but we need to differentiate between 500s that should and shouldn't be retried
			respondWithError(http.StatusTooManyRequests, err)
		} else {
			err := errors.Wrap(err, "error making resolve actions request to deployer")
			respondWithError(http.StatusInternalServerError, err)
		}
		s.Obs.Report(ctx, err)
		return
	}

	resp.Header().Set("Content-Type", "application/json")

	// If we don't have any errors returned, return OK, otherwise set it to
	// UnprocessableEntity.
	status := "200"
	defer func() {
		s.Obs.Counter(ctx, "receiver.runner_resolve_actions", statter.Tags{"status_code": status}, 1)
	}()

	if len(svcResponse.Errors) == 0 {
		resp.WriteHeader(http.StatusOK)
	} else {
		status = "422"
		resp.WriteHeader(http.StatusUnprocessableEntity)
	}

	if err := json.NewEncoder(resp).Encode(&svcResponse); err != nil {
		err := errors.Wrap(err, "failed to encode resolve actions response")
		s.Obs.Report(ctx, err)
		status = "500"
		respondWithError(http.StatusInternalServerError, err)
		return
	}
}

func (s *Servicer) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}
