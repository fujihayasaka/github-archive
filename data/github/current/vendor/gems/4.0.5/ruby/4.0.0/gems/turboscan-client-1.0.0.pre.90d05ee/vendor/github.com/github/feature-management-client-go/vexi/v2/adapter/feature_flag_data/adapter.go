// Package featureflagdata holds the definition and out of the box feature flag dat implementation of the adapter interface.
package featureflagdata

import (
	"context"
	"errors"
	"net/http"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	vexihttp "github.com/github/feature-management-client-go/vexi/v2/internal/http"
	twirphelpers "github.com/github/feature-management-client-go/vexi/v2/internal/twirp-helpers"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	checks "github.com/github/feature-management-protos/gen/go/feature_management/feature_flags/data/v2"
)

const (
	defaultDataAdapterHTTPClientTimeout = 1 * time.Second // defaultDataAdapterHTTPClientTimeout is the default HTTPClient timeout in seconds.
	defaultDataAdapterTotalRetryTimeout = 1 * time.Second // defaultDataAdapterTotalRetryTimeout is the default retry timeout in seconds.
	defaultDataAdapterRetryAttempt      = 3               // defaultDataAdapterRetryAttempt is the number of times the call is retried.
)

// AdapterOptionFunc is the function signature for options for the feature flag data adapter.
type AdapterOptionFunc func(*adapterOptions)

// Adapter is a vexi data Adapter that can communicate with the feature-management-lite service (or feature-flag-data service although that is not planned).
type Adapter struct {
	client            checks.Checks
	httpClient        vexihttp.Client
	totalRetryTimeout time.Duration
}

type adapterOptions struct {
	httpClient vexihttp.Client
	hmacKey    string
}

// FeatureManagementLiteURL is the URL to use when communicating with feature-management-lite in the codespace.
const FeatureManagementLiteURL string = "http://localhost:8090"

// New returns a new Feature Flag Data adapter that can be used to communicate with feature-management-lite in a codespace for development scenarios.
func New(featureFlagDataURL string, options ...AdapterOptionFunc) (*Adapter, error) {
	adapter := &Adapter{}
	o := &adapterOptions{}

	adapter.totalRetryTimeout = defaultDataAdapterTotalRetryTimeout

	// apply options
	for _, opt := range options {
		opt(o)
	}

	if o.httpClient != nil {
		adapter.httpClient = o.httpClient
	} else {
		adapter.httpClient = &http.Client{
			Transport: http.DefaultTransport,
			Timeout:   defaultDataAdapterHTTPClientTimeout,
		}
	}

	// Wrap http client with headers middleware
	if o.hmacKey != "" {
		adapter.httpClient = vexihttp.WithHMACSignature(adapter.httpClient, o.hmacKey)
	}
	adapter.httpClient = vexihttp.WithGitHubUser(adapter.httpClient, "vexi-go")
	adapter.httpClient = vexihttp.WithVexiVersion(adapter.httpClient)
	adapter.client = checks.NewChecksProtobufClient(featureFlagDataURL, adapter.httpClient)

	return adapter, nil
}

// WithDataHTTPClient sets the HTTP client to use.
func WithDataHTTPClient(httpClient *http.Client) AdapterOptionFunc {
	return func(f *adapterOptions) {
		f.httpClient = httpClient
	}
}

// WithDataHMAC provides an HMAC in the event this adapter is talking to feature-flag-data service vs. feature-management-lite which doesn't require it.
func WithDataHMAC(hmacKey string) AdapterOptionFunc {
	return func(f *adapterOptions) {
		f.hmacKey = hmacKey
	}
}

// GetFeatureFlags returns the specified feature flags as a slice. If a feature flag does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular feature flag.
func (adapter *Adapter) GetFeatureFlags(ctx context.Context, names ...string) ([]*featureflag.FeatureFlag, error) {
	if len(names) == 0 {
		return nil, vexi_errors.NewValidationError("names cannot be empty")
	}

	untypedResponse, err := twirphelpers.WithRetry(ctx, defaultDataAdapterRetryAttempt, adapter.totalRetryTimeout, "GetFeatureFlags",
		func(passedCtx context.Context) (interface{}, error) {
			return adapter.client.GetFeatureFlags(passedCtx, &checks.GetFeatureFlagsRequest{Names: names})
		})
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "error getting feature flags from the feature flag data")
	}

	resp, ok := untypedResponse.(*checks.GetFeatureFlagsResponse)
	if !ok {
		return nil, errors.New("error casting response from feature flag data to *checks.GetFeatureFlagsResponse")
	}

	ffMap := make(map[string]*featureflag.FeatureFlag, len(resp.FeatureFlags))
	for _, ff := range resp.FeatureFlags {
		ffMap[ff.Name] = convertDataToVexiFeatureFlag(ff)
	}

	var result []*featureflag.FeatureFlag
	for _, name := range names {
		if flag, ok := ffMap[name]; ok {
			result = append(result, flag)
		}
		// Note: Feature flags that don't exist are simply not included in the slice
	}

	return result, nil
}

// GetSegments returns the specified segments as a slice. If the segment does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular segment.
func (adapter *Adapter) GetSegments(ctx context.Context, names ...string) ([]*segment.Segment, error) {
	if len(names) == 0 {
		return nil, vexi_errors.NewValidationError("names cannot be empty")
	}

	untypedResponse, err := twirphelpers.WithRetry(ctx, defaultDataAdapterRetryAttempt, adapter.totalRetryTimeout, "GetSegments",
		func(passedCtx context.Context) (interface{}, error) {
			return adapter.client.GetSegments(passedCtx, &checks.GetSegmentsRequest{Names: names})
		})
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "error getting segments from feature flag data")
	}

	resp, ok := untypedResponse.(*checks.GetSegmentsResponse)
	if !ok {
		return nil, errors.New("error casting response from feature flag data to *checks.GetSegmentsResponse")
	}

	result := make([]*segment.Segment, 0, len(names))
	segMap := map[string]*checks.Segment{}
	for i := range resp.Segments {
		seg := resp.Segments[i]
		segMap[seg.Name] = seg
	}

	for _, segName := range names {
		if seg, ok := segMap[segName]; ok {
			result = append(result, convertDataToVexiSegment(seg))
		}
		// Note: Segments that don't exist are simply not included in the slice
	}

	return result, nil
}

// Name returns the name of the adapter.
func (adapter *Adapter) Name() string {
	return "FeatureFlagData"
}

// convertDataToVexiFeatureFlag converts a checks.FeatureFlag from feature-flag-data service to a Vexi feature flag.
func convertDataToVexiFeatureFlag(ff *checks.FeatureFlag) *featureflag.FeatureFlag {
	return &featureflag.FeatureFlag{
		Name:               ff.Name,
		BooleanGate:        ff.State == checks.FeatureFlagState_SHIPPED,
		PercentageOfActors: ff.PercentageOfActors,
		PercentageOfCalls:  ff.PercentageOfCalls,
		CustomGates:        ff.CustomGates,
		Segments:           ff.Segments,
		OwningService:      ff.OwningService,
	}
}

// convertDataToVexiSegment converts a checks.Segment from feature-flag-data service to a Vexi segment.
func convertDataToVexiSegment(seg *checks.Segment) *segment.Segment {
	return &segment.Segment{
		Name:   seg.Name,
		Actors: seg.Actors,
	}
}
