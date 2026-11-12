// Package hydro holds the definition and out of the box hydro implementation of the adapter interface.
package hydro

import (
	"cmp"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"slices"
	"time"

	"github.com/cenkalti/backoff/v5"
	"github.com/github/feature-management-client-go/vexi/v2"
	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/helpers"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging/hydro"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/puzpuzpuz/xsync/v3"
	"go.uber.org/zap"
)

const (
	// defaultFeatureTopicName is the name of the feature flag topic (production).
	defaultFeatureTopicName string = "featureflags.vexi.v0.FeatureFlag"

	// defaultSegmentTopicName is the name of the segment topic (production).
	defaultSegmentTopicName string = "featureflags.vexi.v0.Segment"

	// defaultCuratedSegmentTopicName is the name of the curated segment topic (production).
	defaultCuratedSegmentTopicName string = "featureflags.vexi.v0.CuratedSegment"

	// vexiPartitionMax is the highest partition ID we can shard messages into in the
	// feature flag and segment topics. This does not apply to the curated segment topic
	// which only has one partition.
	vexiPartitionMax uint64 = 20

	// defaultMaxBackoffWindow effects the longest time resilient start will wait between retries.
	// There is a randomization factor of 0.5 to 1.5 applied to this value.
	defaultMaxBackoffWindow time.Duration = 5 * time.Minute

	// defaultMaxBlockingWait is the default longest time we will wait for the adapter's cache
	// to be ready. If this time is exceeded, we'll continue and retry in the background until
	// success or a non-retryable error is returned.
	defaultMaxBlockingWait time.Duration = 5 * time.Second
)

type adapterOptions struct {
	featureFlagTopicName   string
	segmentTopicName       string
	curatedSegmentsEnabled bool
	consumerConfig         hydro.ConsumerConfig
	logger                 log.Logger
	statsClient            stats.Client
	tracer                 vexi.Tracer
	telem                  internal.Telemetry
	owningService          string
	allServices            bool
	logOnUpdate            bool
	additionalServices     []string
}

// AdapterOptionFunc is the function signature for options for the Hydro adapter.
type AdapterOptionFunc func(*adapterOptions)

type resilientStartOptions struct {
	maxBackoffWindow time.Duration
	maxBlockingWait  time.Duration
}

// ResilientStartOptionFunc is the function signature for options for the ResilientStart method.
type ResilientStartOptionFunc func(*resilientStartOptions)

// Adapter is the adapter that maintains state in memory by processing two Adapter topics.
type Adapter struct {
	featureFlagTopicName    string
	segmentTopicName        string
	featureFlags            *xsync.MapOf[string, *featureflag.FeatureFlag]
	segments                *xsync.MapOf[string, *segment.Segment]
	segmentTimestamps       *xsync.MapOf[string, time.Time]
	featureProcessor        *messaging.SyncMapProcessor
	segmentProcessor        *messaging.SyncMapProcessor
	curatedSegmentProcessor *messaging.SyncMapProcessor
	telem                   internal.Telemetry
	cacheReadinessService   hydro.CacheReadinessService
	resilientStartFunc      func(ctx context.Context) (chan struct{}, error)
	owningServices          []string
}

// NewAdapter creates a new Hydro adapter that subscribes to feature flags that belong to the
// specified owning service. This is the recommended adapter configuration for optimal
// performance and resource usage.
func NewAdapter(
	ctx context.Context,
	appName, owningService string,
	optionFuncs ...AdapterOptionFunc,
) (*Adapter, error) {
	if owningService == "" {
		return nil, vexi_errors.NewValidationError("owning service cannot be empty")
	}
	return newWithOwningServices(ctx, appName, []string{owningService}, optionFuncs...)
}

// NewAdapterWithOwningServices creates a new Hydro adapter that subscribes to feature flags
// that belong to the specified owning services. This requires more resources compared to
// NewAdapter due to needing to subscribe to multiple partitions.
func NewAdapterWithOwningServices(
	ctx context.Context,
	appName string,
	owningServices []string,
	optionFuncs ...AdapterOptionFunc,
) (*Adapter, error) {
	if len(owningServices) == 0 {
		return nil, vexi_errors.NewValidationError("owning services cannot be empty")
	}
	return newWithOwningServices(ctx, appName, owningServices, optionFuncs...)
}

// NewAdapterWithAllServices creates a new Hydro adapter that subscribes to all feature flags.
// This is the least efficient configuration and should only be used for testing or when you
// need to subscribe to feature flags across all owning services.
func NewAdapterWithAllServices(
	ctx context.Context,
	appName string,
	optionFuncs ...AdapterOptionFunc,
) (*Adapter, error) {
	return newWithOwningServices(ctx, appName, nil, optionFuncs...)
}

func newWithOwningServices(
	ctx context.Context,
	appName string,
	owningServices []string,
	optionFuncs ...AdapterOptionFunc,
) (*Adapter, error) {
	featureFlags := xsync.NewMapOf[string, *featureflag.FeatureFlag]()
	segments := xsync.NewMapOf[string, *segment.Segment]()
	segmentTimestamps := xsync.NewMapOf[string, time.Time]()
	adapter := &Adapter{
		featureFlags:         featureFlags,
		segments:             segments,
		featureFlagTopicName: defaultFeatureTopicName,
		segmentTopicName:     defaultSegmentTopicName,
		segmentTimestamps:    segmentTimestamps,
	}

	options := &adapterOptions{}
	for _, opt := range optionFuncs {
		opt(options)
	}

	err := options.consumerConfig.Validate()
	if err != nil {
		return nil, err
	}

	if appName == "" {
		return nil, vexi_errors.NewValidationError("appName is required")
	}

	if options.logger == nil {
		options.logger = telemetry.NullLogger
	}

	if options.statsClient == nil {
		options.statsClient = stats.NullStatter
	}

	if options.tracer == nil {
		options.tracer = telemetry.NullTracer
	}

	if options.telem == nil {
		adapter.telem = telemetry.NewStandardTelemetry(
			options.logger,
			options.tracer,
			options.statsClient,
		)
	} else {
		adapter.telem = options.telem
	}

	if options.featureFlagTopicName != "" {
		adapter.featureFlagTopicName = options.featureFlagTopicName
	}

	if options.segmentTopicName != "" {
		adapter.segmentTopicName = options.segmentTopicName
	}

	// Remove this logic in the next major version.
	owningServices = append(owningServices, options.additionalServices...)
	owningServices = append(owningServices, options.owningService)
	owningServices = helpers.RemoveDuplicates(owningServices)
	// The struct has a default value of "" on options.owningService
	owningServices = slices.DeleteFunc(owningServices, func(e string) bool {
		return e == ""
	})

	// Store the owning services in the adapter
	adapter.owningServices = owningServices

	adapter.telem.AddTags(stats.Tags{telemetry.LegacyAppNameTagName: appName})
	adapter.telem.AddTags(stats.Tags{telemetry.AppNameTagName: appName})
	adapter.telem.AddFields(zap.String(telemetry.AppNameFieldName, appName))

	adapter.cacheReadinessService = hydro.NewCacheReadinessService(
		adapter.telem,
		options.curatedSegmentsEnabled,
	)
	payloadParser := hydro.NewPayloadParser(adapter.telem)

	featureFlagEntityUpdater := hydro.NewFeatureFlagEntityUpdater(
		adapter.telem,
		adapter.featureFlags,
		payloadParser,
		adapter.cacheReadinessService,
		options.curatedSegmentsEnabled,
		options.logOnUpdate,
		owningServices,
	)
	segmentEntityUpdater := hydro.NewSegmentEntityUpdater(
		adapter.telem,
		adapter.segments,
		payloadParser,
		adapter.cacheReadinessService,
		options.logOnUpdate,
		owningServices,
	)
	curatedSegmentEntityUpdater := hydro.NewCuratedSegmentEntityUpdater(
		adapter.telem,
		adapter.segments,
		adapter.segmentTimestamps,
		payloadParser,
		adapter.cacheReadinessService,
		options.logOnUpdate,
	)

	featureFlagCaughtUpNotifier, _ := featureFlagEntityUpdater.(messaging.CaughtUpNotifier)
	segmentCaughtUpNotifier, _ := segmentEntityUpdater.(messaging.CaughtUpNotifier)
	curatedSegmentCaughtUpNotifier, _ := curatedSegmentEntityUpdater.(messaging.CaughtUpNotifier)

	partitionIDs := make(map[int32]bool)

	if options.allServices || len(owningServices) == 0 {
		// Subscribe to all partitions
		for partitionID := int32(0); partitionID < int32(vexiPartitionMax); partitionID++ {
			partitionIDs[partitionID] = true
		}
	} else {
		for _, service := range owningServices {
			partitionID, err := getPartitionKey(service)
			if err != nil {
				return nil, err
			}
			partitionIDs[partitionID] = true
		}
	}

	featureConsumer, err := hydro.NewSingleTopicStatelessConsumer(
		ctx,
		options.consumerConfig,
		adapter.telem,
		adapter.featureFlagTopicName,
		partitionIDs,
	)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "unable to create feature flag hydro consumer")
	}
	segmentConsumer, err := hydro.NewSingleTopicStatelessConsumer(
		ctx,
		options.consumerConfig,
		adapter.telem,
		adapter.segmentTopicName,
		partitionIDs,
	)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "unable to create segment hydro consumer")
	}

	if options.curatedSegmentsEnabled {
		curatedSegmentConsumer, err := hydro.NewSingleTopicStatelessConsumer(
			ctx,
			options.consumerConfig,
			adapter.telem,
			defaultCuratedSegmentTopicName,
			map[int32]bool{messaging.AllPartitions: true},
		)
		if err != nil {
			return nil, vexi_errors.NewWrappedError(err, "unable to create curated segment hydro consumer")
		}

		adapter.curatedSegmentProcessor = messaging.NewSyncMapProcessor(
			adapter.telem,
			curatedSegmentConsumer,
			messaging.SegmentEntity,
			curatedSegmentConsumer.PartitionIDs,
			curatedSegmentEntityUpdater,
			curatedSegmentCaughtUpNotifier,
		)
	}

	adapter.featureProcessor = messaging.NewSyncMapProcessor(
		adapter.telem,
		featureConsumer,
		messaging.FeatureFlagEntity,
		featureConsumer.PartitionIDs,
		featureFlagEntityUpdater,
		featureFlagCaughtUpNotifier,
	)
	adapter.segmentProcessor = messaging.NewSyncMapProcessor(
		adapter.telem,
		segmentConsumer,
		messaging.SegmentEntity,
		segmentConsumer.PartitionIDs,
		segmentEntityUpdater,
		segmentCaughtUpNotifier,
	)

	adapter.resilientStartFunc = adapter.Start

	return adapter, nil
}

// Start will start the Hydro consumers attached to the adapter and start processing changes.
func (h *Adapter) Start(ctx context.Context) (chan struct{}, error) {
	elapsedTimeFunc := telemetry.NewTimer()
	h.telem.LogInfo(ctx, "Starting hydro adapter")
	err := h.featureProcessor.Start(ctx)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "unable to start feature flag message processor")
	}
	err = h.segmentProcessor.Start(ctx)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "unable to start segment message processor")
	}

	if h.curatedSegmentProcessor != nil {
		err = h.curatedSegmentProcessor.Start(ctx)
		if err != nil {
			return nil, vexi_errors.NewWrappedError(err, "unable to start curated segment message processor")
		}
	}

	go h.featureProcessor.ConsumeMessages(ctx)
	go h.segmentProcessor.ConsumeMessages(ctx)
	if h.curatedSegmentProcessor != nil {
		go h.curatedSegmentProcessor.ConsumeMessages(ctx)
	}

	internalWait := h.cacheReadinessService.WaitForReady()

	go func() {
		<-internalWait
		timeTaken := elapsedTimeFunc()
		h.telem.MetricDistributionMs(ctx, telemetry.HydroAdapterStartupDurationMetricName, stats.Tags{}, timeTaken)
		h.telem.LogInfo(ctx, "Hydro adapter started", zap.Duration(telemetry.HydroAdapterStartupDurationFieldName, timeTaken))
	}()

	return h.cacheReadinessService.WaitForReady(), nil
}

// ResilientStart will block for up to 5 seconds (configurable) for the adapter to start.
// If the adapter hasn't start by that time, this method stops blocking and returns nil.
// It then continues to retry starting in the background until success or a non-retryable
// error is returned. Until the adapter starts, IsEnabled(..) will return false,
// IsEnabledWithDefaultValue(..) will return the default value and IsEnabledWithError(..)
// will return an ErrAdapterNotReady error.
func (h *Adapter) ResilientStart(
	ctx context.Context,
	optionFuncs ...ResilientStartOptionFunc,
) error {
	elapsedTimeFunc := telemetry.NewTimer()
	options := &resilientStartOptions{
		maxBackoffWindow: defaultMaxBackoffWindow,
		maxBlockingWait:  defaultMaxBlockingWait,
	}
	for _, opt := range optionFuncs {
		opt(options)
	}

	tags := stats.Tags{}
	err := h.doResilientStart(ctx, options)
	if err != nil {
		if !errors.Is(err, context.Canceled) {
			tags["error"] = "true"
		}
	}

	h.telem.MetricDistributionMs(ctx, telemetry.HydroAdapterResilientStartDurationMetric, tags, elapsedTimeFunc())
	return err
}

func (h *Adapter) doResilientStart(ctx context.Context, options *resilientStartOptions) error {
	h.telem.LogInfo(
		ctx,
		"Starting hydro adapter with resilience",
		zap.Duration("max_blocking_wait", options.maxBlockingWait),
		zap.Duration("max_backoff_window", options.maxBackoffWindow),
	)

	resilientStartResult := make(chan error, 1)
	backgroundStartTime := time.Now()

	operation := func() (chan struct{}, error) {
		ready, err := h.resilientStartFunc(ctx)
		if err != nil {
			if hydro.IsPermanentHydroError(err) {
				h.telem.MetricCounter(
					ctx,
					telemetry.HydroAdapterStartFailed,
					stats.Tags{"retryable": "false"},
					1,
				)
				return nil, backoff.Permanent(err)
			}

			h.telem.LogInfo(ctx, "Hydro adapter start failed, retrying", zap.Error(err))
			h.telem.MetricCounter(
				ctx,
				telemetry.HydroAdapterStartFailed,
				stats.Tags{"retryable": "true"},
				1,
			)
			return nil, err
		}

		return ready, nil
	}

	go func() {
		defer close(resilientStartResult)

		expBackoff := backoff.NewExponentialBackOff()
		expBackoff.MaxInterval = options.maxBackoffWindow

		backoffOptions := []backoff.RetryOption{
			backoff.WithBackOff(expBackoff),
			backoff.WithMaxElapsedTime(0), // This is set to make the backoff retry forever
		}

		startReady, err := backoff.Retry(ctx, operation, backoffOptions...)
		if err != nil {
			if errors.Is(err, context.Canceled) {
				h.telem.LogWarn(
					ctx,
					"Hydro adapter start canceled due to context cancellation",
					zap.Error(err),
				)
				resilientStartResult <- err
				return
			}
			h.telem.LogError(
				ctx,
				"Failed to start hydro adapter due to non-retryable error",
				zap.Error(err),
			)
			resilientStartResult <- err
			return
		}
		<-startReady

		// Emit background startup duration metric
		backgroundDuration := time.Since(backgroundStartTime)
		h.telem.MetricDistributionMs(
			ctx,
			telemetry.HydroAdapterResilientStartBackgroundDurationMetricName,
			stats.Tags{},
			backgroundDuration,
		)

		// The deferred close makes this not strictly necessary, including for clarity
		resilientStartResult <- nil

		h.telem.LogInfo(ctx, "Successfully started hydro adapter after resilient start")
	}()

	select {
	case resilientStartError := <-resilientStartResult:
		return resilientStartError
	case <-time.After(options.maxBlockingWait):
		h.telem.MetricCounter(
			ctx,
			telemetry.HydroAdapterResilientStartTimeout,
			stats.Tags{},
			1,
		)
		h.telem.LogInfo(
			ctx,
			"Hydro adapter started without fully waiting for data after max blocking wait",
			zap.Duration("max_blocking_wait", options.maxBlockingWait),
		)
		return nil
	}
}

// WithCuratedSegments enables the use of curated segments.
func WithCuratedSegments() AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.curatedSegmentsEnabled = true
	}
}

// WithHydroBrokers sets the comma delimited list of hydro brokers to use for talking with Hydro.
func WithHydroBrokers(brokers string) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.consumerConfig.HydroBrokers = brokers
	}
}

// WithSystemRootCA sets to use the system root CA used when setting production hydro
// communication allowing for automatic certificate rotation without client changes.
// Note that this method is just added for documentation purposes in the client and
// actually is the default if not specified.
func WithSystemRootCA() AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.consumerConfig.HydroRootCA = ""
		o.consumerConfig.IsDevelopment = false
	}
}

// WithLogOnUpdate sets the adapter to log when a feature flag, segment or curatedSegment is updated or deleted.
func WithLogOnUpdate() AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.logOnUpdate = true
	}
}

// WithRootCA sets the root CA used when setting production hydro communication.
func WithRootCA(rootCA string) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.consumerConfig.HydroRootCA = rootCA
		o.consumerConfig.IsDevelopment = false
	}
}

// WithTopics changes the hydro topic names used from the default production ones. This is
// useful in internal use cases where we want to use featureflags-staging or featureflags-lab.
func WithTopics(featureFlagTopicName, segmentTopicName string) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.featureFlagTopicName = featureFlagTopicName
		o.segmentTopicName = segmentTopicName
	}
}

// WithTLSDisabled will disable the Root CA used with production (non-local testing) use cases
// of hydro. This is useful in codespaces.
func WithTLSDisabled() AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.consumerConfig.HydroRootCA = ""
		o.consumerConfig.IsDevelopment = true
	}
}

// WithLogger sets the logger to use for the adapter. NullLogger is used if not set.
func WithLogger(logger log.Logger) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.logger = logger
	}
}

// WithStatsClient sets the stats client to use for the adapter. NullStats is used if not set.
func WithStatsClient(stats stats.Client) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.statsClient = stats
	}
}

// WithTracer sets the tracer to use for the adapter. NullTracer is used if not set.
func WithTracer(tracer vexi.Tracer) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.tracer = tracer
	}
}

// WithKafkaOptions configures the Kafka client with additional options.
// E.g. setting Kafka version, etc.
func WithKafkaOptions(kafkaOptions ...hydropkg.KafkaConfigOption) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.consumerConfig.KafkaOptions = kafkaOptions
	}
}

// Yes this really just helps with testing but it is needed if we are going to use the constructor in tests.
func withTelemetry(telem internal.Telemetry) AdapterOptionFunc {
	return func(o *adapterOptions) {
		o.telem = telem
	}
}

// WithMaxBackoffWindow sets the max backoff window for the adapter to resilient start.
func WithMaxBackoffWindow(maxBackoffWindow time.Duration) ResilientStartOptionFunc {
	return func(o *resilientStartOptions) {
		o.maxBackoffWindow = maxBackoffWindow
	}
}

// WithMaxBlockingWait sets the max blocking wait for the adapter to resilient start.
func WithMaxBlockingWait(maxBlockingWait time.Duration) ResilientStartOptionFunc {
	return func(o *resilientStartOptions) {
		o.maxBlockingWait = maxBlockingWait
	}
}

// Name returns the name of the adapter.
func (h *Adapter) Name() string {
	return "Hydro"
}

// GetSegments returns the specified segments as a slice. If the segment does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular segment.
func (h *Adapter) GetSegments(ctx context.Context, names ...string) ([]*segment.Segment, error) {
	if !h.cacheReadinessService.CheckReady() {
		return nil, vexi_errors.ErrAdapterNotReady
	}

	return h.doGetSegments(names...)
}

func (h *Adapter) doGetSegments(names ...string) ([]*segment.Segment, error) {
	if len(names) == 0 {
		return nil, vexi_errors.NewValidationError("names cannot be empty")
	}

	result := make([]*segment.Segment, 0, len(names))

	for _, name := range names {
		if seg, ok := h.segments.Load(name); ok {
			result = append(result, seg)
		}
		// Note: Segments that don't exist are simply not included in the slice
	}

	return result, nil
}

// GetFeatureFlags returns the specified feature flags as a slice. If a feature flag does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular feature flag.
func (h *Adapter) GetFeatureFlags(ctx context.Context, names ...string) ([]*featureflag.FeatureFlag, error) {
	if !h.cacheReadinessService.CheckReady() {
		return nil, vexi_errors.ErrAdapterNotReady
	}

	return h.doGetFeatureFlags(names...)
}

func (h *Adapter) doGetFeatureFlags(names ...string) ([]*featureflag.FeatureFlag, error) {
	if len(names) == 0 {
		return nil, vexi_errors.NewValidationError("names cannot be empty")
	}

	var result []*featureflag.FeatureFlag

	for _, name := range names {
		if flag, ok := h.featureFlags.Load(name); ok {
			result = append(result, flag)
		}
		// Note: Feature flags that don't exist are simply not included in the slice
	}

	return result, nil
}

// GetAllFlags returns all feature flags the adapter knows about, sorted by flag name.
// Will return an ErrAdapterNotReady error if the cache is not ready yet.
func (h *Adapter) GetAllFlags() ([]*featureflag.FeatureFlag, error) {
	if !h.cacheReadinessService.CheckReady() {
		return nil, vexi_errors.ErrAdapterNotReady
	}

	return h.doGetAllFlags(), nil
}

func (h *Adapter) doGetAllFlags() []*featureflag.FeatureFlag {
	vals := make([]*featureflag.FeatureFlag, 0, h.featureFlags.Size())
	h.featureFlags.Range(func(_ string, flag *featureflag.FeatureFlag) bool {
		vals = append(vals, flag)
		return true
	})
	slices.SortFunc(vals, func(a, b *featureflag.FeatureFlag) int {
		return cmp.Compare(a.Name, b.Name)
	})
	return vals
}

// getPartitionKey returns a partition key from 0 through VexiPartitionMax - 1.
func getPartitionKey(owningService string) (int32, error) {
	hash := sha256.New()
	_, err := hash.Write([]byte(owningService))
	if err != nil {
		return -1, err
	}
	hashSum := hash.Sum(nil)
	hashInt := binary.BigEndian.Uint64(hashSum[:8])
	partitionID := int32(hashInt % vexiPartitionMax) //nolint:gosec // intentional conversion overflow should not happen.
	return partitionID, nil
}
