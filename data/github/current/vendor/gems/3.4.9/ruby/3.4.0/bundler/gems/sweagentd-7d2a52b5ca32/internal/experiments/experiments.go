// Package experiments provides functionality to interact with ExP.
// It includes methods to interact with the ExP API, get variation assignments,
// and manage traffic filters.
package experiments

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
)

// Client defines the interface for interacting with the ExP API.
type Client interface {
	// GetFeatureAssignment retrieves the feature assignment for a given feature name,
	// randomization unit, and traffic filters. It leverages the assignments cache to
	// avoid unnecessary API calls. If the assignment is found, it returns the assignment
	// and a boolean indicating success. If not found, it returns nil and false. This is
	// because we can error calling the TAS, but we don't want to propagate that error
	// back to the caller. The caller should handle the case where the assignment wasn't
	// found successfully, usually by falling back to the control experience.
	GetFeatureAssignment(ctx context.Context, featureName string, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (assignment *Assignment, found bool)

	// NewTrafficFiltersDefaults is a convenience method to create default traffic filters
	// for a request based on the traffic filters already registered with ExP. These are
	// available for use by anyone out-of-the-box. They are:
	// 1. Repository
	// 2. OrgID
	// 3. UserKind
	//
	// UserKind requires an API call to connect the user's ID to their UserKind (GitHub,
	// Microsoft Copilot, or Microsoft org).
	NewTrafficFiltersDefaults(ctx context.Context, twirpClient githubtwirp.ClientInterface, defaultFilters *FilterProps) (TrafficFilters, error)
}

// TrafficFilterManager defines the interface for managing traffic filters.
type TrafficFilterManager interface {
	Set(trafficFilter *TrafficFilter)
	SetHTTPHeaders(req *http.Request)
}

var _ Client = &ExperimentsClient{}

// ExperimentsClient is the implementation of the Client interface.
// The name follows the pattern used in this codebase where concrete types
// are explicitly named with their domain prefix.
//
//nolint:revive // Established API name, changing would break consumers
type ExperimentsClient struct {
	// TODO (jtmcg): Create a generic logging interface
	obsv             observability.Exporters
	url              url.URL
	http             *http.Client
	AssignmentsCache *AssignmentsCache
	TrafficFilters   TrafficFilterManager
}

const (
	// VSCodeExtensionNameHeader is used to identify the VS Code extension name on
	// all TAS requests associated with the experiment client.
	VSCodeExtensionNameHeader = "X-VSCode-ExtensionName"
)

// ExpTransport wraps an HTTP RoundTripper to add experiment-specific headers.
type ExpTransport struct {
	RoundTripper  http.RoundTripper
	extensionName string
}

// RoundTrip implements the http.RoundTripper interface, adding required headers to requests.
func (et *ExpTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if et.extensionName != "" {
		req.Header.Set(VSCodeExtensionNameHeader, et.extensionName)
	}
	return et.RoundTripper.RoundTrip(req)
}

// ExperimentConfig holds configuration parameters for the experiments client.
type ExperimentConfig struct {
	Endpoint      string
	ExtensionName string
	Timeout       time.Duration
	CacheConfig   CacheConfig
}

const defaultTimeout = 1000 * time.Millisecond

// NewClientFromConfig creates a new experiments client using the given config
func NewClientFromConfig(ctx context.Context, cfg *config.Config, obsv observability.Exporters) Client {
	var experimentsClient Client

	if cfg.Environment == config.EnvironmentProxima {
		experimentsClient = NewProximaClient()
	} else {
		experimentConfig := ExperimentConfig{
			Endpoint:      cfg.ExperimentationAPIURL,
			ExtensionName: cfg.CopilotIntegrationID,
			Timeout:       cfg.ExperimentsTimeout,
			CacheConfig:   NewDefaultCacheConfig(),
		}
		experimentsClient = NewClient(ctx, obsv, experimentConfig)
	}

	return experimentsClient
}

// NewClient creates a new ExperimentsClient with the provided parameters.
func NewClient(ctx context.Context, obsv observability.Exporters, ecfg ExperimentConfig) *ExperimentsClient {
	tr := &ExpTransport{
		RoundTripper:  observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "experiments"),
		extensionName: ecfg.ExtensionName,
	}

	u, err := url.Parse(ecfg.Endpoint)
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).Fatal("failed to parse baseURL", kvp.Err(err))
	}

	timeout := ecfg.Timeout
	if timeout <= time.Duration(0) {
		timeout = defaultTimeout
	}

	httpClient := &http.Client{
		Transport: tr,
		Timeout:   timeout,
	}

	client := &ExperimentsClient{
		obsv: obsv,
		url:  *u,
		http: httpClient,
	}

	trafficFilters := &TrafficFilters{RepositoryFilter, OrgsFilter, UserKindFilter}

	client.TrafficFilters = trafficFilters
	client.AssignmentsCache = NewAssignmentsCache(ctx, obsv, ecfg.CacheConfig)
	return client
}

// FilterProps defines the default filters provided by the experiment client.
// These are values we can send to ExP to enable traffic filters out of the box.
type FilterProps struct {
	RepoID int64
	OrgID  int64
	UserID int64 // Used to fetch org inclusion for UserKind
}

// NewTrafficFiltersDefaults creates a new TrafficFilters instance with the provided parameters.
func (e *ExperimentsClient) NewTrafficFiltersDefaults(ctx context.Context, twirpClient githubtwirp.ClientInterface, defaultFilterProps *FilterProps) (TrafficFilters, error) {
	trafficFilters := TrafficFilters{
		RepositoryFilter,
		OrgsFilter,
		UserKindFilter,
		RepositoryVisibilityHeader,
	}

	if defaultFilterProps == nil {
		return trafficFilters, nil
	}

	// Default Traffic Filters come from what's pre-defined in ExP
	// https://exp.microsoft.com/admin/ExperimentTrafficFilters/vscodeexpws/padawan?workspaceId=dbd12384-5001-4e90-a863-526321eaf233
	RepositoryFilter.Value = strconv.FormatInt(defaultFilterProps.RepoID, 10)
	OrgsFilter.Value = strconv.FormatInt(defaultFilterProps.OrgID, 10)

	visibility, err := getRepositoryVisibility(ctx, twirpClient, defaultFilterProps.RepoID)
	if err != nil {
		return trafficFilters, fmt.Errorf("failed to get repository visibility: %w", err)
	}
	RepositoryVisibilityHeader.Value = visibility

	userKind, err := getUserKind(ctx, twirpClient, uint64(defaultFilterProps.UserID))
	if err != nil {
		return trafficFilters, fmt.Errorf("failed to get user kind: %w", err)
	}
	UserKindFilter.Value = userKind.Hash()

	return trafficFilters, nil
}

// CopilotExpAssignmentResponse represents the response structure from the ExP API for feature assignments.
type CopilotExpAssignmentResponse struct {
	Features          []string          `json:"Features"`
	Flights           map[string]string `json:"Flights"`
	Configs           []ConfigEntry     `json:"Configs"`
	ParameterGroups   any               `json:"ParameterGroups"`
	FlightingVersion  int               `json:"FlightingVersion"`
	ImpressionID      string            `json:"ImpressionId"`
	AssignmentContext string            `json:"AssignmentContext"`
}

// ConfigEntry represents a single configuration entry in the ExP API response.
type ConfigEntry struct {
	ID         string         `json:"Id"`
	Parameters map[string]any `json:"Parameters"`
}

// GetFeatureAssignment retrieves the feature assignment for a given feature name.
func (e *ExperimentsClient) GetFeatureAssignment(ctx context.Context, featureName string, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (assignment *Assignment, found bool) {
	assignments, err := e.getAssignments(ctx, randomizationUnit, trafficFilters)
	if err != nil {
		// Don't block the request if we can't get assignments
		e.obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("failed to get assignment for %s", featureName), kvp.Err(err))
		return nil, false
	}
	return assignments.GetVariation(featureName)
}

// getAssignments retrieves the assignments for the given randomization unit and traffic filters.
func (e *ExperimentsClient) getAssignments(ctx context.Context, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (*Assignments, error) {
	if randomizationUnit == nil {
		return nil, errors.New("randomization unit is required for assignments")
	}
	e.obsv.LoggerWithTelemetry(ctx).Info("getting assignments", kvp.String("randomizationUnit", randomizationUnit.Header.String()))
	e.TrafficFilters.Set(randomizationUnit)

	// Generate cache key for current request
	cacheKey := GenerateCacheKey(randomizationUnit, trafficFilters)

	// Check cache for existing valid entry
	if e.AssignmentsCache != nil {
		if cachedAssignments := e.AssignmentsCache.Get(cacheKey); cachedAssignments != nil {
			e.obsv.LoggerWithTelemetry(ctx).Info("using cached assignments")
			return cachedAssignments, nil
		}
	}

	e.obsv.LoggerWithTelemetry(ctx).Info("assignments cache miss, fetching new assignments")
	resp, err := e.getExperiments(ctx, trafficFilters)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).Error("failed to get experiments", kvp.Err(err))
		return nil, err
	}

	assignments := NewVSCodeAssignments(resp)
	e.AssignmentsCache.Set(cacheKey, assignments)

	return assignments, nil
}

func (e *ExperimentsClient) getExperiments(ctx context.Context, trafficFilters TrafficFilters) (*CopilotExpAssignmentResponse, error) {
	ctx, span := e.obsv.Tracer.Start(ctx, "experiments.getExperiments")
	defer span.End()

	logger := e.obsv.LoggerWithTelemetry(ctx)
	logger.Info("getting assignment experiments")

	// Set or update any traffic filters
	for _, tf := range trafficFilters {
		e.TrafficFilters.Set(tf)
	}

	start := time.Now()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, e.url.String(), http.NoBody)

	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	e.TrafficFilters.SetHTTPHeaders(req)

	resp, err := e.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	e.obsv.LogWithDuration(ctx, logger, start, "experiments.getExperiments.httpRequest")

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var response CopilotExpAssignmentResponse
	err = json.NewDecoder(resp.Body).Decode(&response)
	if err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	logger.Info("retrieved assignment experiments")

	return &response, nil
}
