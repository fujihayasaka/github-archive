package networksettings

import (
	"context"
	"encoding/json"
	"io"
	"strconv"
	"strings"

	"fmt"
	"net/http"
	"net/url"

	"github.com/github/go-kvp"

	oteltrace "go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/tracing"

	"github.com/github/launch/pkg/mu"

	gohmac "github.com/github/go-auth/hmac"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/types"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/appcontext"
)

type Service struct {
	obs                      *observability.Observability
	db                       deployer.AzpResourcesLoader
	verifier                 *hmac.HTTPVerifier
	networkServiceURL        string
	networkServiceHmacSecret string
	httpClient               *ahttp.RetryClient
	ghTwirpClient            ghtwirp.Client
}

func NewService(
	obs *observability.Observability,
	db deployer.AzpResourcesLoader,
	verifier *hmac.HTTPVerifier,
	networkServiceURL string,
	networkServiceHmacSecret string,
	httpClient *ahttp.RetryClient,
	ghTwirpClient ghtwirp.Client,
) *Service {
	return &Service{
		obs:                      obs,
		db:                       db,
		verifier:                 verifier,
		networkServiceURL:        networkServiceURL,
		networkServiceHmacSecret: networkServiceHmacSecret,
		httpClient:               httpClient,
		ghTwirpClient:            ghTwirpClient,
	}
}

type RequestContext struct {
	apiVersion    string
	entityID      types.GlobalID
	databaseID    string
	runnerGroupID string
}

func NewRequestContext(
	apiVersion string,
	entityID types.GlobalID,
	databaseID string,
	runnerGroupID string,
) *RequestContext {
	return &RequestContext{
		apiVersion:    apiVersion,
		entityID:      entityID,
		databaseID:    databaseID,
		runnerGroupID: runnerGroupID,
	}
}

const networkSettingsRoute = "/actions/network_configuration"

var unassignedResponseNetworkID = strings.Repeat("0", 64)

type NetworkServiceComputeResourcesResponse struct {
	ID                   string                                       `json:"id"`
	Service              string                                       `json:"service"`
	NetworkConfiguration *NetworkServiceComputeResourcesConfiguration `json:"networkConfiguration"`
}
type NetworkServiceComputeResourcesConfiguration struct {
	ID               string                                          `json:"id"`
	Enabled          bool                                            `json:"enabled"`
	NetworkResources []NetworkServiceComputeResourcesNetworkResource `json:"networkResources"`
}

type NetworkServiceComputeResourcesNetworkResource struct {
	ID                  string   `json:"id"`
	Name                string   `json:"name"`
	State               string   `json:"state"`
	ConfiguredResources []string `json:"configuredResources"`
	Location            string   `json:"location"`
	SubnetID            string   `json:"subnetId"`
	BusinessID          string   `json:"businessId"`
	Type                string   `json:"type"`
}

type NetworkServiceConfigurationResponse struct {
	ResourceID     string `json:"resourceId"`
	Location       string `json:"location"`
	State          string `json:"state"`
	SubnetID       string `json:"subnetId"`
	TargetServices []struct {
		Name                string   `json:"name"`
		ConfiguredResources []string `json:"configuredResources"`
		Enabled             bool     `json:"enabled"`
	} `json:"targetServices"`
}

type VnetInjection struct {
	Enabled bool     `json:"enabled"`
	Subnets []Subnet `json:"subnets"`
}

type Subnet struct {
	ResourceID string `json:"resourceId"`
	Region     string `json:"region"`
}

type LaunchNetworkConfigurationResponse struct {
	ID            *string       `json:"id"`
	IsEnabled     bool          `json:"isEnabled"`
	VnetInjection VnetInjection `json:"vnetInjection"`
}

func (s *Service) HandleGetNetworkSettings(resp http.ResponseWriter, request *http.Request) {
	ctx, span := tracing.Start(request.Context())
	defer span.End()

	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	reqbody, err := io.ReadAll(request.Body)
	if err != nil {
		s.respondWithError(ctx, http.StatusBadRequest, err, resp, span)
		return
	}

	if err := s.verifier.Verify(ctx, request, reqbody); err != nil {
		s.respondWithError(ctx, http.StatusForbidden, err, resp, span)
		return
	}

	requestContext, httpStatusCode, err := s.extractQueryParams(ctx, request.URL)
	if err != nil {
		s.respondWithError(ctx, httpStatusCode, err, resp, span)
		return
	}

	networkServiceRequest, err := s.createHTTPRequest(requestContext)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp, span)
		return
	}

	networkServiceResponse, err := s.httpClient.Do(networkServiceRequest)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp, span)
		return
	}
	defer networkServiceResponse.Body.Close()

	if networkServiceResponse.StatusCode != http.StatusOK {
		// pass through non-200 responses to runner
		s.respondWithError(ctx, networkServiceResponse.StatusCode, fmt.Errorf("Network service returned a status of %d", networkServiceResponse.StatusCode), resp, span)
		return
	}

	// only parse the response if the request was successful

	computeResources, err := s.parseAPIResponse(networkServiceResponse)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp, span)
		return
	}
	// The API returns NotFound if the resource is not registered, which was already handled above

	resp.Header().Set("Content-Type", "application/json")

	outgoingBody := s.convertAPIResponse(ctx, computeResources)
	err = json.NewEncoder(resp).Encode(outgoingBody)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp, span)
		return
	}
}

func (s *Service) getRequestEndpoint(apiVersion string, runnerGroupID string) string {
	if apiVersion == "1" {
		return fmt.Sprintf("%s/api/v1/configurations/services/actions/computeResources/%s?enableNewBehavior=true", s.networkServiceURL, runnerGroupID)
	}
	return fmt.Sprintf("%s/api/v1/configurations/services/actions/computeResources/%s", s.networkServiceURL, runnerGroupID)
}

func (s *Service) parseAPIResponse(networkServiceResponse *http.Response) (NetworkServiceComputeResourcesResponse, error) {
	networkServiceResponseBody, err := io.ReadAll(networkServiceResponse.Body)
	if err != nil {
		return NetworkServiceComputeResourcesResponse{}, err
	}

	// Future: may not unmarshal or modify the response body in launch, merely pass it through to actions-dotnet
	var incoming NetworkServiceComputeResourcesResponse
	err = json.Unmarshal(networkServiceResponseBody, &incoming)
	if err != nil {
		return NetworkServiceComputeResourcesResponse{}, err
	}

	return incoming, nil
}

func (s *Service) convertAPIResponse(ctx context.Context, computeResourcesResponse NetworkServiceComputeResourcesResponse) LaunchNetworkConfigurationResponse {
	if computeResourcesResponse.NetworkConfiguration == nil {
		// Unknown compute resource
		return LaunchNetworkConfigurationResponse{
			ID:        nil,
			IsEnabled: true,
			VnetInjection: VnetInjection{
				Enabled: false,
				Subnets: []Subnet{},
			},
		}
	}

	networkConfiguration := *computeResourcesResponse.NetworkConfiguration
	if networkConfiguration.ID == unassignedResponseNetworkID || len(networkConfiguration.NetworkResources) == 0 {
		// Unassigned compute resource
		id := unassignedResponseNetworkID
		return LaunchNetworkConfigurationResponse{
			ID:        &id,
			IsEnabled: true,
			VnetInjection: VnetInjection{
				Enabled: false,
				Subnets: []Subnet{},
			},
		}
	}

	containsRequestedResource := false
	subnets := []Subnet{}

	for _, resource := range networkConfiguration.NetworkResources {
		if resource.Type != "NetworkSettings" {
			s.obs.Log(ctx, "Unexpected network resource type", kvp.String("gh.launch.network_resource.type", resource.Type))
			continue
		}
		containsRequestedResource = true
		subnets = append(subnets, Subnet{
			ResourceID: resource.SubnetID,
			Region:     resource.Location,
		})
	}

	return LaunchNetworkConfigurationResponse{
		ID:        &networkConfiguration.ID,
		IsEnabled: networkConfiguration.Enabled,
		VnetInjection: VnetInjection{
			Enabled: containsRequestedResource,
			Subnets: subnets,
		},
	}
}

func (s *Service) createHTTPRequest(requestContext *RequestContext) (*http.Request, error) {
	networkServiceRunnerURL := s.getRequestEndpoint(requestContext.apiVersion, requestContext.runnerGroupID)

	// Create the request object
	req, err := http.NewRequest("GET", networkServiceRunnerURL, nil)
	if err != nil {
		return nil, err
	}
	requestHMAC := gohmac.NewRequestHMAC(s.networkServiceHmacSecret)

	req.Header.Add("Authorization", "HMAC-SHA256 "+requestHMAC.String())
	req.Header.Add("Subject", requestContext.databaseID)
	req.Header.Add("User-Agent", "launch-receiver")

	return req, nil
}

func (s *Service) extractQueryParams(ctx context.Context, url *url.URL) (*RequestContext, int, error) {
	// Empty string is currently okay. Once a new version is standardized this should be required.
	version := url.Query().Get("apiVersion")

	tenantID := url.Query().Get("tenantId")
	if tenantID == "" {
		err := fmt.Errorf("tenantId is required")
		return nil, http.StatusBadRequest, err
	}

	res, found, err := s.db.GetByTenantID(ctx, tenantID)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	if !found {
		err := fmt.Errorf("tenantId not found")
		return nil, http.StatusNotFound, err
	}

	// get the database id from the global id
	_, databaseIDInt, err := res.EntityID.Decode()
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}

	runnerGroupID := url.Query().Get("runnerGroupId")
	if runnerGroupID == "" {
		err = fmt.Errorf("runnerGroupId is required")
		return nil, http.StatusBadRequest, err
	}

	databaseIDString := strconv.FormatInt(databaseIDInt, 10)

	return NewRequestContext(version, res.EntityID, databaseIDString, runnerGroupID), -1, nil
}

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		mu.Get(networkSettingsRoute, s.HandleGetNetworkSettings),
	}
}

func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Service) respondWithError(ctx context.Context, code int, err error, resp http.ResponseWriter, span oteltrace.Span) {
	// Skip logging 404s since they are expected and can generate a lot of noise
	if code != http.StatusNotFound {
		s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
	}

	http.Error(resp, http.StatusText(code), code)
}
