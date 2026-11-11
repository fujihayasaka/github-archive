package hydro

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"path"
	"slices"
	"strings"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging/hydro"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"github.com/github/go-stats"
	"go.uber.org/zap"
)

const (
	featureFlagCacheFileName = "feature_flags.json"
	segmentCacheFileName     = "segments.json"
	defaultEnvironmentPrefix = "FF_OVERRIDE_"
)

// PersistentHostAdapter is an interface for managing persistent hosts.
// It embeds Hydro Adapter and provides additional methods for work with persistent caches - file and env variables.
type PersistentHostAdapter struct {
	Adapter
	overrideCache     map[string]*featureflag.FeatureFlag
	cachePresent      bool
	flushInterval     time.Duration
	fileStorePath     string
	environmentPrefix string
}

// PersistentAdapterOptionFunc is a function that configures a PersistentHostAdapter.
type PersistentAdapterOptionFunc func(*persistentAdapterOptions)

// persistentAdapterOptions holds the options for creating a PersistentHostAdapter.
type persistentAdapterOptions struct {
	flushInterval      time.Duration
	adapterOptionFuncs []AdapterOptionFunc
	environmentPrefix  string
}

// defaultPersistentAdapterOptions returns the default options for creating a PersistentHostAdapter.
func defaultPersistentAdapterOptions() *persistentAdapterOptions {
	return &persistentAdapterOptions{
		flushInterval:      60 * time.Second,
		adapterOptionFuncs: []AdapterOptionFunc{},
		environmentPrefix:  defaultEnvironmentPrefix,
	}
}

// WithFlushInterval sets the interval for cache serialization
func WithFlushInterval(interval time.Duration) PersistentAdapterOptionFunc {
	return func(o *persistentAdapterOptions) {
		o.flushInterval = interval
	}
}

// WithEnvironmentOverridePrefix sets the prefix for environment variable overrides
// The default prefix is "FF_OVERRIDE_"
func WithEnvironmentOverridePrefix(environmentPrefix string) PersistentAdapterOptionFunc {
	return func(o *persistentAdapterOptions) {
		o.environmentPrefix = environmentPrefix
	}
}

// WithHydroAdapterOptions adds options to be passed to the underlying HydroAdapter
func WithHydroAdapterOptions(optionFuncs ...AdapterOptionFunc) PersistentAdapterOptionFunc {
	return func(o *persistentAdapterOptions) {
		o.adapterOptionFuncs = append(o.adapterOptionFuncs, optionFuncs...)
	}
}

// NewPersistentHostAdapter creates a new PersistentHostAdapter.
func NewPersistentHostAdapter(ctx context.Context, appName, owningService, persistentCacheDirectory string, optionFuncs ...PersistentAdapterOptionFunc) (*PersistentHostAdapter, error) {
	options := defaultPersistentAdapterOptions()
	for _, opt := range optionFuncs {
		opt(options)
	}

	adapter, err := NewAdapter(ctx, appName, owningService, options.adapterOptionFuncs...)
	if err != nil {
		return nil, err
	}

	return newPersistentHostAdapter(ctx, *adapter, persistentCacheDirectory, options)
}

// NewPersistentAdapterWithOwningServices creates a new PersistentHostAdapter with owning services.
func NewPersistentAdapterWithOwningServices(ctx context.Context, appName string, owningServices []string, persistentCacheDirectory string, optionFuncs ...PersistentAdapterOptionFunc) (*PersistentHostAdapter, error) {
	options := defaultPersistentAdapterOptions()
	for _, opt := range optionFuncs {
		opt(options)
	}

	adapter, err := NewAdapterWithOwningServices(ctx, appName, owningServices, options.adapterOptionFuncs...)
	if err != nil {
		return nil, err
	}

	return newPersistentHostAdapter(ctx, *adapter, persistentCacheDirectory, options)
}

// NewPersistentAdapterWithAllServices creates a new PersistentHostAdapter with all services.
func NewPersistentAdapterWithAllServices(ctx context.Context, appName, persistentCacheDirectory string, optionFuncs ...PersistentAdapterOptionFunc) (*PersistentHostAdapter, error) {
	options := defaultPersistentAdapterOptions()
	for _, opt := range optionFuncs {
		opt(options)
	}

	adapter, err := NewAdapterWithAllServices(ctx, appName, options.adapterOptionFuncs...)
	if err != nil {
		return nil, err
	}

	return newPersistentHostAdapter(ctx, *adapter, persistentCacheDirectory, options)
}

func newPersistentHostAdapter(ctx context.Context, adapter Adapter, persistentCacheDirectory string, options *persistentAdapterOptions) (*PersistentHostAdapter, error) {
	persistentAdapter := PersistentHostAdapter{
		Adapter:           adapter,
		flushInterval:     options.flushInterval,
		fileStorePath:     persistentCacheDirectory,
		environmentPrefix: options.environmentPrefix,
		overrideCache:     make(map[string]*featureflag.FeatureFlag),
	}

	err := persistentAdapter.prepareCacheDir()
	if err != nil {
		persistentAdapter.telem.LogError(ctx, "Failed to prepare cache path", zap.Error(err))
		return nil, vexi_errors.NewWrappedError(err, "failed to prepare cache path")
	}

	return &persistentAdapter, nil
}

// Start is not supported by PersistentHostAdapter
func (a *PersistentHostAdapter) Start(ctx context.Context) (chan struct{}, error) {
	err := initCache(ctx, a)
	if err != nil {
		return nil, err
	}

	return a.Adapter.Start(ctx)
}

type persistentHostStartOptions struct {
	maxCacheEmptyBlockingWait time.Duration
	resilientStartOptionFuncs []ResilientStartOptionFunc
}

// PersistentHostStartOptionFunc is the function signature for options for the ResilientStart method.
type PersistentHostStartOptionFunc func(*persistentHostStartOptions)

// WithMaxEmptyCacheBlockingWait sets the max blocking Start wait for the adapter when no cache is present on disk
// See also WithMaxBlockingWait
func WithMaxEmptyCacheBlockingWait(maxEmptyCacheBlockingWait time.Duration) PersistentHostStartOptionFunc {
	return func(o *persistentHostStartOptions) {
		o.maxCacheEmptyBlockingWait = maxEmptyCacheBlockingWait
	}
}

// WithResilientStartOptions adds options to be passed to Hydro's ResilientStart
func WithResilientStartOptions(optionFuncs ...ResilientStartOptionFunc) PersistentHostStartOptionFunc {
	return func(o *persistentHostStartOptions) {
		o.resilientStartOptionFuncs = append(o.resilientStartOptionFuncs, optionFuncs...)
	}
}

// ResilientStart starts by loading any file cache and environmental overrides,
// then will block up for 1 seconds (default) for the adapter to start.
// If the adapter hasn't start by that time, this method stops blocking and returns nil.
// Environmental overrides apply for the lifetime of the adapter.
// The file cache, if available), will apply until the adapter successfully gets data from hydro.
// Retry starting in the background until success or a non-retryable error is returned.
// Precedence: environmental override > hydro (if loaded) > cached value (if available) > default value
func (a *PersistentHostAdapter) ResilientStart(ctx context.Context, optionFuncs ...PersistentHostStartOptionFunc) error {
	elapsedTimeFunc := telemetry.NewTimer()
	err := initCache(ctx, a)
	if err != nil {
		return err
	}

	options := &persistentHostStartOptions{
		maxCacheEmptyBlockingWait: defaultMaxBlockingWait,
	}
	for _, opt := range optionFuncs {
		opt(options)
	}

	rsOptions := &resilientStartOptions{
		maxBackoffWindow: defaultMaxBackoffWindow,
		maxBlockingWait:  1 * time.Second, // default for pha is lower
	}
	for _, opt := range options.resilientStartOptionFuncs {
		opt(rsOptions)
	}

	if !a.cachePresent {
		rsOptions.maxBlockingWait = options.maxCacheEmptyBlockingWait
	}

	tags := stats.Tags{}
	err = a.doResilientStart(ctx, rsOptions)
	if err != nil {
		if !errors.Is(err, context.Canceled) {
			tags["error"] = "true"
		}
	}

	a.telem.MetricDistributionMs(ctx, telemetry.PersistentHostAdapterResilientStartDurationMetricName, tags, elapsedTimeFunc())
	return err
}

func initCache(ctx context.Context, a *PersistentHostAdapter) error {
	loadCacheFileStart := time.Now()
	if err := a.loadFeatureFlagsFromFile(ctx); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to load feature flags from file")
	}

	if err := a.loadSegmentsFromFile(ctx); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to load segments from file")
	}

	a.loadEnvOverrides(ctx)

	loadCacheFileDuration := time.Since(loadCacheFileStart)
	a.telem.MetricDistributionMs(ctx, telemetry.PersistentHostAdapterCacheLoadDurationMetricName, stats.Tags{}, loadCacheFileDuration)

	s := &cacheSerializer{
		cache:                 a,
		cacheReadinessService: a.cacheReadinessService,
		interval:              a.flushInterval,
		telem:                 a.telem,
	}
	s.Start(ctx)

	return nil
}

// GetSegments returns the specified segments as a slice. If the segment does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular segment.
func (a *PersistentHostAdapter) GetSegments(ctx context.Context, names ...string) ([]*segment.Segment, error) {
	// the PHA version skips the readiness test
	return a.doGetSegments(names...)
}

// GetFeatureFlags returns the specified feature flags as a slice. If a feature flag does not exist, it will not be included in the returned slice.
// May return other errors if there was a general error not associated to fetching a particular feature flag.
func (a *PersistentHostAdapter) GetFeatureFlags(ctx context.Context, names ...string) ([]*featureflag.FeatureFlag, error) {
	// the PHA version skips the readiness test
	// but because we are using additional cache, it worth to check if the names are empty as well
	if len(names) == 0 {
		return nil, vexi_errors.NewValidationError("names cannot be empty")
	}

	namesMinusOverrides := []string{}
	var result []*featureflag.FeatureFlag

	for _, name := range names {
		// check if we have an override for this name
		override, hasOverride := a.overrideCache[name]
		if hasOverride {
			result = append(result, override)
		} else {
			namesMinusOverrides = append(namesMinusOverrides, name)
		}
	}

	// if we got requests for overrides only, return them
	if len(namesMinusOverrides) == 0 {
		return result, nil
	}

	// normal get feature flags call
	// this will never return an error because the namesMinusOverrides slice is guaranteed to be non-empty
	adapterResults, err := a.doGetFeatureFlags(namesMinusOverrides...)
	if err != nil {
		return nil, err
	}

	// combine the results - append the slice results
	result = append(result, adapterResults...)

	return result, nil
}

// validateFilePath checks if the file path is valid.
func (a *PersistentHostAdapter) prepareCacheDir() error {
	stats, err := os.Stat(a.fileStorePath)

	switch {
	case err != nil && os.IsNotExist(err):
		// Directory does not exist, try to create it
		err := os.MkdirAll(a.fileStorePath, 0o750)
		if err != nil {
			return fmt.Errorf("failed to create directory for file path: %w", err)
		}
	case err != nil:
		// Some other error occurred during Stat
		return fmt.Errorf("failed to check file path: %w", err)
	case !stats.IsDir():
		// Path exists but is not a directory
		return fmt.Errorf("file path %s is not a directory", a.fileStorePath)
	}

	// Make sure we can write to the path
	f, err := os.CreateTemp(a.fileStorePath, ".write_test")
	if err != nil {
		return fmt.Errorf("file path %s is not writable: %w", a.fileStorePath, err)
	}
	_ = f.Close()
	_ = os.Remove(f.Name())

	return nil
}

func (a *PersistentHostAdapter) readCacheFile(ctx context.Context, filePath string, destination interface{}) error {
	// Not an error if file missing, potentially first run
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		a.telem.MetricCounter(ctx, telemetry.PersistentHostAdapterNoFileCacheCountName, stats.Tags{}, 1)
		return nil
	}

	file, err := os.Open(filePath)
	if err != nil {
		return vexi_errors.NewWrappedError(err, "failed to open feature flags file")
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(destination); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to decode feature flags file")
	}

	return nil
}

func (a *PersistentHostAdapter) loadFeatureFlagsFromFile(ctx context.Context) error {
	var fileFlags []featureflag.FeatureFlag
	err := a.readCacheFile(ctx, path.Join(a.fileStorePath, featureFlagCacheFileName), &fileFlags)
	if err != nil {
		return vexi_errors.NewWrappedError(err, "failed to load feature flags from file")
	}

	if len(fileFlags) > 0 {
		a.cachePresent = true
	}

	// Use owning services from the adapter for filtering
	owningServices := a.owningServices

	// Populate the cache maps with filtering by owning services
	for _, f := range fileFlags {
		// Apply the same filtering logic as the FeatureFlagEntityUpdater
		if len(owningServices) > 0 && !slices.Contains(owningServices, f.OwningService) {
			a.telem.LogWarn(ctx, "Skipping feature flag from file cache due to owning service filtering",
				zap.String("feature_flag", f.Name),
				zap.String("owning_service", f.OwningService),
				zap.Strings("configured_owning_services", owningServices))
			continue // Skip this feature flag as it's not for our service
		}
		a.featureFlags.Store(f.Name, &f)
	}

	return nil
}

func (a *PersistentHostAdapter) loadSegmentsFromFile(ctx context.Context) error {
	var segments []segment.Segment
	err := a.readCacheFile(ctx, path.Join(a.fileStorePath, segmentCacheFileName), &segments)
	if err != nil {
		return fmt.Errorf("failed to load segments from file: %w", err)
	}

	if len(segments) > 0 {
		a.cachePresent = true
	}

	// Use owning services from the adapter for filtering
	owningServices := a.owningServices

	// Populate the cache maps with filtering by owning services
	for _, s := range segments {
		// Apply the same filtering logic as the SegmentEntityUpdater:
		// Only check owning service if the segment has a non-empty owning service. This is for non default segments like curated segments.
		shouldCheckOwning := s.OwningService != "" && len(owningServices) > 0
		if shouldCheckOwning && !slices.Contains(owningServices, s.OwningService) {
			a.telem.LogWarn(ctx, "Skipping segment from file cache due to owning service filtering",
				zap.String("segment", s.Name),
				zap.String("owning_service", s.OwningService),
				zap.Strings("configured_owning_services", owningServices))
			continue // Skip this segment as it's not for our service
		}
		a.segments.Store(s.Name, &s)
	}
	return nil
}

// loadEnvOverrides loads all environment variables that start with the prefix FF_OVERRIDE_ into a slice.
func (a *PersistentHostAdapter) loadEnvOverrides(ctx context.Context) {
	ffOverrides := make(map[string]bool)

	for _, env := range os.Environ() {
		if !strings.HasPrefix(env, a.environmentPrefix) {
			continue
		}

		// assumes env var value is in the format "FF_OVERRIDE_KEY=VALUE"
		// ignore found, this is an environment variable, it will always have an =
		key, value, _ := strings.Cut(env, "=")
		key = strings.ToLower(strings.TrimPrefix(key, a.environmentPrefix))
		if key == "" {
			a.telem.LogError(ctx, "Invalid environment variable override format, override string must be at least 1 character long")
			continue
		}
		val, ok := a.parseBooleanString(ctx, value)
		if !ok {
			a.telem.LogError(ctx, "Invalid environment variable override value, must be a boolean", zap.String("key", key))
			continue
		}
		ffOverrides[key] = val
	}

	for key, value := range ffOverrides {
		featureFlag := featureflag.FeatureFlag{
			Name:        key,
			BooleanGate: value,
		}

		a.overrideCache[key] = &featureFlag

		// track each override with a log message and metric
		a.telem.LogWarn(ctx, "Feature flag override from environment variable", zap.String("key", key), zap.Bool("value", value))
		a.telem.MetricCounter(ctx, telemetry.PersistentHostAdapterEnvironmentOverrideMetricName,
			stats.Tags{"feature_flag.key": key, "value": fmt.Sprintf("%t", value)}, 1)
	}

	// track the total number of overrides
	if len(ffOverrides) > 0 {
		a.telem.MetricCounter(ctx, telemetry.PersistentHostAdapterEnvironmentOverrideCountName, nil, int64(len(ffOverrides)))
	}
}

// parseBooleanString parses a string into a boolean value.
// Acceptable values are: "true", "false", "1", "0", "yes", "no", "enabled", "disabled", "on", "off"
func (a *PersistentHostAdapter) parseBooleanString(ctx context.Context, value string) (enabled, ok bool) {
	// Normalize the string once
	value = strings.ToLower(strings.TrimSpace(value))
	// Check for common truthy values
	switch value {
	case "true", "1", "yes", "enabled", "on", "y":
		return true, true
	case "false", "0", "no", "disabled", "off", "n":
		return false, true
	default:
		// If not in our known list, set to false and return not ok
		a.telem.LogError(ctx, "Unknown boolean value for override. Override will be ignored!")
		return false, false
	}
}

// saveItemsToFile serializes the cache in json. write and swap used to keep atomic
func (a *PersistentHostAdapter) saveItemsToFile(ctx context.Context, items interface{}, fileName string) error {
	data, err := json.Marshal(items)
	if err != nil {
		return vexi_errors.NewWrappedError(err, "failed to marshal data")
	}

	// Generate random string suffix
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, 8)
	for i := range b {
		// #nosec G404 - This is used for sampling metrics, not for security purposes
		b[i] = charset[rand.IntN(len(charset))]
	}
	randomSuffix := string(b)

	// Use atomic write pattern with random suffix before .tmp extension
	tempFile := path.Join(a.fileStorePath, fileName) + "." + randomSuffix + ".tmp"

	// Ensure the temp file is cleaned up if there's an error
	defer func() {
		if err != nil {
			// Only attempt to remove if the file exists
			if _, statErr := os.Stat(tempFile); statErr == nil {
				if removeErr := os.Remove(tempFile); removeErr != nil {
					a.telem.LogError(ctx, "Failed to clean up temporary file",
						zap.String("file", tempFile),
						zap.Error(removeErr))
				}
			}
		}
	}()

	if err = os.WriteFile(tempFile, data, 0o600); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to write data to temp file")
	}

	// Atomic file replacement
	if err = os.Rename(tempFile, path.Join(a.fileStorePath, fileName)); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to replace file")
	}

	return nil
}

// collectFeatureFlags gathers all feature flags with timestamps
func (a *PersistentHostAdapter) collectFeatureFlags() []featureflag.FeatureFlag {
	flags := []featureflag.FeatureFlag{}

	a.featureFlags.Range(func(key string, value *featureflag.FeatureFlag) bool {
		flags = append(flags, *value)
		return true
	})

	return flags
}

// collectSegments gathers all segments with timestamps
func (a *PersistentHostAdapter) collectSegments() []segment.Segment {
	segments := []segment.Segment{}

	a.segments.Range(func(key string, value *segment.Segment) bool {
		segments = append(segments, *value)
		return true
	})

	return segments
}

func (a *PersistentHostAdapter) serializeCache(ctx context.Context) error {
	elapsedTimeFunc := telemetry.NewTimer()
	dir := a.fileStorePath
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to create directory for cache files")
	}

	// Save feature flags
	flags := a.collectFeatureFlags()
	if err := a.saveItemsToFile(ctx, flags, featureFlagCacheFileName); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to save feature flags")
	}

	// Save segments
	segments := a.collectSegments()
	if err := a.saveItemsToFile(ctx, segments, segmentCacheFileName); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to save segments")
	}

	timeTaken := elapsedTimeFunc()
	a.telem.MetricDistributionMs(ctx, telemetry.PersistentHostAdapterCacheSerializationDurationMetricName, stats.Tags{}, timeTaken)
	return nil
}

// Name returns the name of the adapter.
func (a *PersistentHostAdapter) Name() string {
	return "PersistentHostAdapter"
}

type cacheable interface {
	serializeCache(context.Context) error
}

type cacheSerializer struct {
	cache                 cacheable
	cacheReadinessService hydro.CacheReadinessService
	interval              time.Duration
	telem                 internal.Telemetry
}

func (c *cacheSerializer) Start(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(c.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				c.telem.LogInfo(ctx, "Stopping cache serializer")
				return
			case <-ticker.C:
				if c.cacheReadinessService.CheckReady() {
					// Save state to file every interval
					if err := c.cache.serializeCache(ctx); err != nil {
						c.telem.LogError(ctx, "Error saving cache to file", zap.Error(err))
					}
				}
			}
		}
	}()
}
