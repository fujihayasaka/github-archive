package status

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/github/go-kvp"
	"github.com/go-chi/chi"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/auth/hkdf"
	deployer "github.com/github/launch/services/deploy/environment"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/receiver"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/stringutils"
)

type Servicer struct {
	Log           logger.Logger
	Stats         statter.Statter
	Verifier      hkdf.Verifier
	Deployer      deployer.Environment
	IsLab         bool
	IsEnterprise  bool
	ReceiverURL   string
	GHTwirpClient ghtwirp.Client
}

var _ mu.Servicer = (*Servicer)(nil)

const (
	getEnvironmentCallbackRoute = `/actions/build/{workflowID:[0-9A-Za-z-]+}/environments/{environmentName}`
)

type Gate struct {
	ID               string `json:"id"`
	Type             string `json:"type"`
	TimeoutInMinutes int    `json:"timeoutInMinutes"`
	State            string `json:"state"`
}

type EnvironmentResponse struct {
	Name  string `json:"name"`
	Gates []Gate `json:"gates"`
}

func (s *Servicer) Routes() []mu.Route {
	return []mu.Route{
		// Authenticated via a base64 encoded signature passed as a HTTP header.
		mu.Get(getEnvironmentCallbackRoute, s.HandleGetEnvironment),
	}
}
func (s *Servicer) HandleGetEnvironment(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPJobStatusLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: getEnvironmentCallbackRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	wfid := chi.URLParam(req, "workflowID")
	env := chi.URLParam(req, "environmentName")

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.actions.plan_id", wfid),
		kvp.String("gh.launch.environment.name", env),
	)

	if s.IsLab {
		reqStr, err := stringutils.HTTPRequestToString(req)
		if err == nil {
			s.Log.Log(ctx, "debugging job status postback request", kvp.Any("gh.launch.get_environment.request", reqStr))
		}
	}

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "receiver.environment", statter.Tags{"status_code": fmt.Sprintf("%d", code)}, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusBadRequest, errors.Wrap(err, "could not read http body"))
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

	erq := &deployer.GetOrCreateEnvironmentRequest{
		WorkflowID:      wfid,
		EnvironmentName: env,
	}

	res, err := s.Deployer.GetOrCreateEnvironment(ctx, erq)

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

	s.Stats.Counter(ctx, "receiver.environment", statter.Tags{"status_code": "200"}, 1)

	gates := make([]Gate, 0, len(res.Gates))
	for _, g := range res.Gates {
		gates = append(gates, Gate{
			ID:               g.Id.GetGlobalId(),
			TimeoutInMinutes: int(g.TimeoutInMinutes),
			Type:             g.GetType(),
			State:            "", // Not yet used
		})
	}

	environmentResponse := EnvironmentResponse{
		Name:  res.Name,
		Gates: gates,
	}

	resp.Header().Set("Content-Type", "application/json")
	resp.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(resp).Encode(&environmentResponse); err != nil {
		err := errors.Wrap(err, "failed to encode enviroment response")
		if svcerr.CallerShouldReportError(err) {
			s.Log.Report(ctx, err)
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}
}

func (s *Servicer) ServiceContext(r *http.Request) {
	appcontext.SetupServiceContext(r)
}
