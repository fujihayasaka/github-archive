package accountdetails

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/github/go-kvp"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/utils/appcontext"

	terrors "github.com/github/launch/types/errors"
)

type Service struct {
	obs           *observability.Observability
	db            deployer.AzpResourcesLoader
	verifier      *hmac.HTTPVerifier
	ghTwirpClient ghtwirp.Client
}

func NewService(
	obs *observability.Observability,
	db deployer.AzpResourcesLoader,
	verifier *hmac.HTTPVerifier,
	ghTwirpClient ghtwirp.Client,
) *Service {
	return &Service{
		obs:           obs,
		db:            db,
		verifier:      verifier,
		ghTwirpClient: ghTwirpClient,
	}
}

const accountDetailsRoute = "/actions/account_details"

func (s *Service) HandleGetAccountDetails(resp http.ResponseWriter, request *http.Request) {
	ctx, span := tracing.Start(request.Context())
	defer span.End()

	body, err := io.ReadAll(request.Body)

	if err != nil {
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}

	if err := s.verifier.Verify(ctx, request, body); err != nil {
		s.respondWithError(ctx, http.StatusForbidden, err, resp)
		return
	}

	tenantID := request.URL.Query().Get("tenantId")

	if tenantID == "" {
		s.respondWithError(ctx, http.StatusBadRequest, errors.New("tenantId required"), resp)
		return
	}

	res, found, err := s.db.GetByTenantID(ctx, tenantID)

	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	if !found {
		s.respondWithError(ctx, http.StatusNotFound, errors.New("tenantId not found"), resp)
		return
	}

	entityID := res.EntityID

	checkEntityExists := false
	if s.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.ActionsAccountDetailsCheckEntityExists, entityID) {
		checkEntityExists, err = strconv.ParseBool(request.URL.Query().Get("checkEntityExists"))
		if err != nil {
			// default to not checking entity for backwards compatibility
			checkEntityExists = false
		}

	}

	response, err := s.ghTwirpClient.GetAccountDetails(ctx, entityID)

	if err != nil {
		errorCode := http.StatusInternalServerError
		if checkEntityExists && terrors.IsNotFoundError(err) {
			errorCode = http.StatusNotFound
		}

		s.respondWithError(ctx, errorCode, err, resp)
		return
	}

	jsonDecoderError := json.NewEncoder(resp).Encode(response)

	if jsonDecoderError != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	resp.WriteHeader(http.StatusOK)
}

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		mu.Get(accountDetailsRoute, s.HandleGetAccountDetails),
	}
}

func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Service) respondWithError(ctx context.Context, code int, err error, resp http.ResponseWriter) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))

	span.RecordError(err)
	http.Error(resp, http.StatusText(code), code)
}
