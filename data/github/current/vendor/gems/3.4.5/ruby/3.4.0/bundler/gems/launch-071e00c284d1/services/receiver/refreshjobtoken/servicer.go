package refreshjobtoken

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/github/go-kvp"
	"github.com/go-chi/chi"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/auth/hkdf"
	svcerr "github.com/github/launch/services/errors"
	tk "github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/services/receiver"
	"github.com/github/launch/utils/appcontext"
)

type Servicer struct {
	Log          logger.Logger
	Stats        statter.Statter
	Verifier     hkdf.Verifier
	TokenService tk.LaunchTokenService
	ReceiverURL  string
}

var _ mu.Servicer = (*Servicer)(nil)

const (
	tokenRefreshRoute = `/actions/build/{workflowID:[0-9A-Za-z-]+}/jobs/{jobID}/refresh_tokens`
)

type ServiceResponse struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
}

func (s *Servicer) Routes() []mu.Route {
	return []mu.Route{
		mu.Patch(tokenRefreshRoute, s.HandleTokenRefresh),
	}
}

func (s *Servicer) HandleTokenRefresh(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPRefreshTokenLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: tokenRefreshRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	workflowID := chi.URLParam(req, "workflowID")
	jobID := chi.URLParam(req, "jobID")

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actions.plan_id", workflowID), kvp.String("gh.launch.job.id", jobID))

	respondWithError := func(code int, err error) {
		s.Stats.Counter(ctx, "InvalidTokenRequest", nil, 1)
		s.Log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusBadRequest, errors.Wrap(err, "could not read http body"))
		return
	}

	if isValid, err := receiver.VerifySignature(s.Verifier, req, data, s.ReceiverURL); err != nil {
		respondWithError(http.StatusBadRequest, err)
		return
	} else if !isValid {
		respondWithError(http.StatusUnauthorized, errors.New("Signature verification failed"))
		return
	}

	var token tokens.AccessToken
	if err := json.Unmarshal(data, &token); err != nil {
		err := errors.Wrap(err, "Error unmarshalling token data")
		s.Log.Report(ctx, err)
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	tokenReq := tk.RefreshTokenRequest{WorkflowId: workflowID, Token: token.Token}
	refreshedToken, err := s.TokenService.RefreshToken(ctx, &tokenReq)
	if err != nil {
		err := errors.Wrap(err, "Token RPC call to deployer failed")
		if svcerr.CallerShouldReportError(err) {
			s.Log.Report(ctx, err)
		}
		if strings.Contains(err.Error(), "invalid installation token") {
			respondWithError(http.StatusUnauthorized, err)
		} else {
			respondWithError(http.StatusInternalServerError, err)
		}
		return
	}

	expiresAt := refreshedToken.ExpiresAt.AsTime()

	svcResponse := ServiceResponse{
		Token:     refreshedToken.Token,
		ExpiresAt: expiresAt.Format(time.RFC3339Nano),
	}

	resp.Header().Set("Content-Type", "application/json")
	resp.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(resp).Encode(&svcResponse); err != nil {
		err := errors.Wrap(err, "failed to encode token refresh response")
		s.Log.Report(ctx, err)
		respondWithError(http.StatusInternalServerError, err)
		return
	}
}

func (s *Servicer) ServiceContext(r *http.Request) {
	appcontext.SetupServiceContext(r)
}
