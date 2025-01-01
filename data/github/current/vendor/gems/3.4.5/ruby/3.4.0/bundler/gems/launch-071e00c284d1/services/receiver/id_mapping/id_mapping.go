package idmapping

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"

	"github.com/github/launch/utils/appcontext"
)

type Service struct {
	obs      *observability.Observability
	db       deployer.AzpResourcesLoader
	verifier *hmac.HTTPVerifier
}

func NewService(
	obs *observability.Observability,
	db deployer.AzpResourcesLoader,
	verifier *hmac.HTTPVerifier,
) *Service {
	return &Service{
		obs:      obs,
		db:       db,
		verifier: verifier,
	}
}

const idMappingRoute = "/actions/id_mapping"

type Response struct {
	TenantID             string `json:"tenantId"`
	EntityID             string `json:"entityId"`
	Environment          string `json:"environment"`
	PipelinesScaleUnitID string `json:"pipelinesScaleUnitId,omitempty"`
}

// provide two-way mapping between tenantID (VSSF host ID) and entityID (aka GitHub globalID)
func (s *Service) HandleGetIDMapping(resp http.ResponseWriter, request *http.Request) {
	ctx, span := tracing.Start(request.Context())
	defer span.End()

	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

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
	entityID := request.URL.Query().Get("entityId")

	if tenantID == "" && entityID == "" {
		err := errors.New("tenantId and entityId can't be both empty")
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}

	if tenantID != "" && entityID != "" {
		err := errors.New("tenantId and entityId can't be both set")
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}

	response := &Response{}
	if tenantID != "" {
		res, found, err := s.db.GetByTenantID(ctx, tenantID)
		if err != nil {
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		if !found {
			resp.WriteHeader(http.StatusNotFound)
			return
		}

		response.TenantID = tenantID
		response.EntityID = res.EntityID.String()
		response.Environment = res.Environment
	}

	if entityID != "" {
		environment := request.URL.Query().Get("environment")
		if environment == "" {
			environment = launchconfig.ProductionAppEnv.String()
		}
		res, found, err := s.db.GetByGlobalID(ctx, types.NewGlobalID(ctx, entityID), environment)
		if err != nil {
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		if !found {
			resp.WriteHeader(http.StatusNotFound)
			return
		}

		response.TenantID = res.TenantID
		response.EntityID = entityID
		response.Environment = environment
		response.PipelinesScaleUnitID = res.PipelinesScaleUnitID.String()
	}

	if err := json.NewEncoder(resp).Encode(response); err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	resp.WriteHeader(http.StatusOK)
}

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		mu.Get(idMappingRoute, s.HandleGetIDMapping),
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
