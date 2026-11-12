// Package vexi contains all the domain logic of the library.
package vexi

import (
	"context"
	"errors"
	randv2 "math/rand/v2"
	"strconv"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/internal"

	eval "github.com/github/feature-management-client-go/vexi/v2/internal/gateevaluation"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// Span attribute constants for tracing
const (
	spanAttrDefaultValue        = "gh.vexi.default_value"
	spanAttrActorCount          = "gh.vexi.actor_count"
	spanAttrDefaultValueUsed    = "gh.vexi.default_value_used"
	spanAttrResult              = "gh.vexi.result"
	spanAttrEmptyActorIndices   = "gh.vexi.empty_actor_indices"
	spanAttrFeatureFlagFound    = "gh.vexi.feature_flag_found"
	spanAttrSegmentCount        = "gh.vexi.segment_count"
	spanAttrCustomGateCount     = "gh.vexi.custom_gate_count"
	spanAttrCustomGateEvaluator = "gh.vexi.custom_gate_evaluator"
	spanAttrFeatureFlagKey      = "feature_flag.key"
	spanAttrEmptyActorsPassed   = "gh.vexi.empty_actors_passed" //nolint:gosec // This is not a credential, it's a telemetry attribute name
)

type sampleRate float64

// SamplingRate represents a percentage rate for sampling highly emitted metrics
const (
	SamplingRate01Percent sampleRate = 0.01
	SamplingRate05Percent sampleRate = 0.05
	SamplingRate10Percent sampleRate = 0.10
	SamplingRate20Percent sampleRate = 0.20
	SamplingRate25Percent sampleRate = 0.25
	SamplingRate50Percent sampleRate = 0.50
)

// Client holds all the configuration for the vexi feature flag client.
type Client struct {
	adapter               Adapter
	gateEvaluationService NonActorGateEvaluator
	telem                 internal.Telemetry
	sampleRate            float64
	customGatesEvaluator  CustomGatesEvaluator
}

type options struct {
	logger               log.Logger
	statsClient          stats.Client
	sampleRate           float64
	tracer               Tracer
	customGatesEvaluator CustomGatesEvaluator
}

// Tracer is the interface used by vexi for creating spans for enabled checks.
type Tracer interface {
	// Start creates a span and a context.Context containing the newly-created span.
	//
	// If the context.Context provided in `ctx` contains a Span then the newly-created
	// Span will be a child of that span, otherwise it will be a root span. This behavior
	// can be overridden by providing `WithNewRoot()` as a SpanOption, causing the
	// newly-created Span to be a root span even if `ctx` contains a Span.
	//
	// When creating a Span it is recommended to provide all known span attributes using
	// the `WithAttributes()` SpanOption as samplers will only have access to the
	// attributes provided when a Span is created.
	//
	// Any Span that is created MUST also be ended. This is the responsibility of the user.
	// Implementations of this API may leak memory or other resources if Spans are not ended.
	Start(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span)
}

// CustomGatesEvaluator is the interface for evaluating custom gates.
type CustomGatesEvaluator interface {
	IsEnabled(ctx context.Context, logger log.Logger, customGates []string, actors ...string) (bool, error)
	Name() string
}

// NonActorGateEvaluator is the interface for evaluating non-actor gates. TODO: Make this privat https://github.com/github/feature-management/issues/2174.
type NonActorGateEvaluator interface {
	EvaluateBooleanGate(featureFlag featureflag.FeatureFlag) bool
	EvaluatePercentageOfCallsGate(featureFlag featureflag.FeatureFlag) bool
	EvaluatePercentageOfActorsGate(featureFlag featureflag.FeatureFlag, actors ...string) bool
}

// NewVexiClient returns a new Vexi client.
func NewVexiClient(ctx context.Context, a Adapter, appName string, opts ...OptionFunc) (*Client, error) {
	// This will accept an array of OptionFuncs to configure the client.
	// The options will include adapter to use, logging interface, metrics interface, user-agent information.
	if a == nil {
		return nil, vexi_errors.NewValidationError("adapter cannot be nil")
	}

	if appName == "" {
		return nil, vexi_errors.NewValidationError("appName cannot be empty")
	}

	vexiClient := &Client{
		gateEvaluationService: &eval.Service{},
	}

	o := &options{}
	for _, opt := range opts {
		opt(o)
	}

	if o.logger == nil {
		o.logger = telemetry.NullLogger
	}

	if o.statsClient == nil {
		o.statsClient = stats.NullStatter
	}
	vexiClient.sampleRate = o.sampleRate

	if o.tracer == nil {
		o.tracer = telemetry.NullTracer
	}

	vexiClient.telem = telemetry.NewStandardTelemetry(o.logger, o.tracer, o.statsClient)

	vexiClient.customGatesEvaluator = o.customGatesEvaluator

	// Add owning app name to all metrics
	vexiClient.telem.AddTags(stats.Tags{
		telemetry.LegacyAppNameTagName: appName,
		telemetry.AppNameTagName:       appName,
	})

	// Add owning app name to all logs
	vexiClient.telem.AddFields(zap.String(telemetry.AppNameFieldName, appName))

	vexiClient.telem.LogInfo(ctx, "initializing vexi-go")

	if vexiClient.customGatesEvaluator != nil {
		vexiClient.telem.LogInfo(ctx,
			"Using custom gate evaluator",
			zap.String(telemetry.CustomGateEvaluatorNameFieldName, vexiClient.customGatesEvaluator.Name()))
	}

	vexiClient.adapter = a

	return vexiClient, nil
}

// OptionFunc is the function signature for options for vexi
type OptionFunc func(*options)

// WithLogger sets the logger to use.
func WithLogger(logger log.Logger) OptionFunc {
	return func(o *options) {
		o.logger = logger
	}
}

// WithStatsClient sets the stats client to use.
func WithStatsClient(statsClient stats.Client) OptionFunc {
	return func(o *options) {
		o.statsClient = statsClient
	}
}

// WithTracer sets the tracer to use.
func WithTracer(tracer Tracer) OptionFunc {
	return func(o *options) {
		o.tracer = tracer
	}
}

// WithCustomGatesEvaluator sets the custom gate evaluator to use.
func WithCustomGatesEvaluator(customGatesEvaluator CustomGatesEvaluator) OptionFunc {
	return func(o *options) {
		o.customGatesEvaluator = customGatesEvaluator
	}
}

// WithSampling samples heavily emitted metrics (enabled check), but does not sample metrics like ready start time.
// Do use this *instead* of giving WithStatsClient a client that has a stats.WithSampleRate option set
func WithSampling(rate sampleRate) OptionFunc {
	return func(o *options) {
		o.sampleRate = float64(rate)
	}
}

// IsEnabledWithDefaultValue returns true if the feature flag is enabled for any of the given actors for the specified feature flag. If any error occurs it returns the default value provided.
func (v *Client) IsEnabledWithDefaultValue(ctx context.Context, featureFlagName string, defaultValue bool, actors ...Actor) bool {
	ctx, span := v.telem.StartTrace(ctx,
		"Vexi.IsEnabledWithDefaultValue",
		trace.WithSpanKind(trace.SpanKindInternal),
		trace.WithAttributes(
			attribute.String(spanAttrFeatureFlagKey, featureFlagName),
			attribute.Bool(spanAttrDefaultValue, defaultValue),
			attribute.Int(spanAttrActorCount, len(actors)),
		))
	defer span.End()

	result, _, err := v.isEnabledWithDetails(ctx, "IsEnabledWithDefaultValue", featureFlagName, actors...)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			v.telem.LogDebug(
				ctx,
				"context cancelled while checking if feature flag is enabled",
				zap.String(telemetry.FeatureFlagFieldName, featureFlagName),
			)
		}

		// Don't log "feature flag not found" as an error since it's a normal case
		if !errors.Is(err, vexi_errors.ErrFeatureFlagNotFound) {
			errorMetricTags := stats.Tags{
				telemetry.FeatureFlagTag: featureFlagName,
				telemetry.MethodTag:      "IsEnabledWithDefaultValue",
			}

			switch {
			case errors.Is(err, vexi_errors.ErrFeatureFlagNameRequired):
				errorMetricTags[telemetry.ErrorCauseTagName] = telemetry.ReasonFeatureFlagNameEmpty
			case errors.Is(err, vexi_errors.ErrAdapterNotReady):
				errorMetricTags[telemetry.ErrorCauseTagName] = telemetry.ReasonAdapterNotReady
			default:
				errorMetricTags[telemetry.ErrorCauseTagName] = telemetry.ReasonUnknownError
			}

			flagField := zap.String(telemetry.FeatureFlagFieldName, featureFlagName)

			v.telem.LogWithError(ctx, err, "error determining if flag is enabled", flagField)
			v.telem.MetricCounter(ctx, telemetry.VexiEnabledCheckErrorMetricName, errorMetricTags, 1)
		}

		// Set method-specific span attributes for the fallback scenario
		span.SetAttributes(
			attribute.Bool(spanAttrDefaultValueUsed, true),
			attribute.Bool(spanAttrResult, defaultValue),
		)

		return defaultValue
	}

	// Set method-specific span attributes for successful evaluation
	span.SetAttributes(
		attribute.Bool(spanAttrDefaultValueUsed, false),
		attribute.Bool(spanAttrResult, result),
	)
	return result
}

// IsEnabledWithError returns true if the feature flag is enabled for any of the given actors for the specified feature flag. If any error occurs it will be returned and can be checked.
func (v *Client) IsEnabledWithError(ctx context.Context, featureFlagName string, actors ...Actor) (bool, error) {
	ctx, span := v.telem.StartTrace(ctx,
		"Vexi.IsEnabledWithError",
		trace.WithSpanKind(trace.SpanKindInternal),
		trace.WithAttributes(
			attribute.String(spanAttrFeatureFlagKey, featureFlagName),
			attribute.Int(spanAttrActorCount, len(actors)),
		))
	defer span.End()

	result, _, err := v.isEnabledWithDetails(ctx, "IsEnabledWithError", featureFlagName, actors...)

	// Set method-specific span attributes for the result
	span.SetAttributes(
		attribute.Bool(spanAttrResult, result),
	)

	return result, err
}

// isEnabledWithDetails returns the result, result reason, and error for feature flag evaluation.
// This is the internal method that contains the core logic for feature flag evaluation.
func (v *Client) isEnabledWithDetails(ctx context.Context, methodName, featureFlagName string, actors ...Actor) (bool, string, error) {
	if featureFlagName == "" {
		v.telem.MetricCounter(ctx, telemetry.VexiEmptyFeatureFlagInputMetricName, stats.Tags{}, 1)
		return false, telemetry.ReasonFeatureFlagNameEmpty, vexi_errors.ErrFeatureFlagNameRequired
	}

	elapsedTimeFunc := telemetry.NewTimer()

	emptyActorsIndices := make([]int, 0)
	vexiActors := make([]string, len(actors))
	for i, a := range actors {
		vexiID := ""

		if a == nil || a.VexiID() == "" {
			emptyActorsIndices = append(emptyActorsIndices, i)
		} else {
			vexiID = a.VexiID()
		}

		vexiActors[i] = vexiID
	}

	emptyActorsPassed := false
	if len(emptyActorsIndices) > 0 {
		emptyActorsPassed = true
		v.telem.LogError(
			ctx,
			"actors at specified indices in the feature flag check were empty",
			zap.Ints(telemetry.EmptyOrNilActorsIndexFieldName, emptyActorsIndices))
		telemetry.AddAttributesToSpan(ctx,
			attribute.Bool(spanAttrEmptyActorsPassed, true),
			attribute.IntSlice(spanAttrEmptyActorIndices, emptyActorsIndices),
		)
	} else {
		telemetry.AddAttributesToSpan(ctx, attribute.Bool(spanAttrEmptyActorsPassed, false))
	}

	result := false
	resultReason := telemetry.ReasonAllChecksFalse
	defer func(r *bool) {
		tags := stats.Tags{
			telemetry.EmptyActorsPassedTag: strconv.FormatBool(emptyActorsPassed),
			telemetry.FeatureFlagTag:       featureFlagName,
			telemetry.EnabledResultTag:     strconv.FormatBool(*r),
			telemetry.ResultReason:         resultReason,
			telemetry.MethodTag:            methodName,
		}

		// Record metrics
		if v.sampleRate > 0 {
			// #nosec G404 - This is used for sampling metrics, not for security purposes
			rndShouldSample := randv2.Float64()
			if v.sampleRate > rndShouldSample {
				tags[telemetry.SampleRate] = strconv.FormatFloat(v.sampleRate, 'f', -1, 64)
				v.telem.MetricDistributionMs(ctx, telemetry.EnabledDurationMetricName, tags, elapsedTimeFunc())
			}
		} else {
			v.telem.MetricDistributionMs(ctx, telemetry.EnabledDurationMetricName, tags, elapsedTimeFunc())
		}
	}(&result)

	featureFlags, err := v.adapter.GetFeatureFlags(ctx, featureFlagName)
	if err != nil {
		result = false
		switch {
		case errors.Is(err, vexi_errors.ErrAdapterNotReady):
			resultReason = telemetry.ReasonAdapterNotReady
		case errors.Is(err, context.Canceled):
			resultReason = telemetry.ReasonEvaluationCancelled
			err = vexi_errors.NewWrappedError(err, "error getting feature flag from the adapter")
		default:
			resultReason = telemetry.ReasonEvaluationFailed
		}

		if errors.Is(err, context.Canceled) {
			telemetry.SetSpanStatus(ctx, codes.Ok, "")
		} else {
			telemetry.RecordErrorToSpan(ctx, err)
			telemetry.SetSpanStatus(ctx, codes.Error, "")
		}
		return result, resultReason, err
	}

	var featureFlag *featureflag.FeatureFlag
	for _, ff := range featureFlags {
		if ff != nil && ff.Name == featureFlagName {
			featureFlag = ff
			break
		}
	}
	if featureFlag == nil {
		result = false
		resultReason = telemetry.ReasonNotFound
		err := vexi_errors.ErrFeatureFlagNotFound
		telemetry.RecordErrorToSpan(ctx, err)
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return result, resultReason, err
	}

	// Add feature flag metadata to span
	telemetry.AddAttributesToSpan(ctx,
		attribute.Bool(spanAttrFeatureFlagFound, true),
		attribute.Int(spanAttrSegmentCount, len(featureFlag.Segments)),
		attribute.Int(spanAttrCustomGateCount, len(featureFlag.CustomGates)),
	)

	switch {
	case v.gateEvaluationService.EvaluateBooleanGate(*featureFlag):
		result = true
		resultReason = telemetry.ReasonFullyEnabled
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return true, resultReason, nil
	case v.gateEvaluationService.EvaluatePercentageOfCallsGate(*featureFlag):
		result = true
		resultReason = telemetry.ReasonPercentageOfCalls
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return true, resultReason, nil
	case v.gateEvaluationService.EvaluatePercentageOfActorsGate(*featureFlag, vexiActors...):
		result = true
		resultReason = telemetry.ReasonPercentageOfActors
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return true, resultReason, nil
	}

	if len(featureFlag.Segments) > 0 {
		segments, err := v.adapter.GetSegments(ctx, featureFlag.Segments...)
		if err != nil {
			segmentsField := zap.Strings(telemetry.SegmentFieldName, featureFlag.Segments)
			// If we get an error log it, but don't return so we can continue to try evaluate the custom gates.
			if errors.Is(err, context.Canceled) {
				resultReason = telemetry.ReasonEvaluationCancelled
				v.telem.LogDebug(ctx, "context cancelled while getting segments from the adapter", segmentsField)
				telemetry.SetSpanStatus(ctx, codes.Ok, "")
			} else {
				resultReason = telemetry.ReasonEvaluationFailed
				v.telem.LogWithError(ctx, err, "error getting segments from the adapter", segmentsField)
				telemetry.RecordErrorToSpan(ctx, err)
			}
		} else if anyActorInSegments(segments, vexiActors) {
			result = true

			// Given the way we've implemented curated segments, reason custom gate will actually show up as reason actor match for those that
			// have equivalent curated segments.
			resultReason = telemetry.ReasonActorMatch
			telemetry.SetSpanStatus(ctx, codes.Ok, "")
			return true, resultReason, nil
		}
	}

	if v.customGatesEvaluator == nil || len(featureFlag.CustomGates) == 0 {
		result = false
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return false, resultReason, nil
	}

	telemetry.AddAttributesToSpan(ctx, attribute.String(spanAttrCustomGateEvaluator, v.customGatesEvaluator.Name()))

	isEnabled, err := v.customGatesEvaluator.IsEnabled(ctx, v.telem.GetLogger(), featureFlag.CustomGates, vexiActors...)
	if err != nil {
		result = false
		if errors.Is(err, context.Canceled) {
			resultReason = telemetry.ReasonEvaluationCancelled
			err = vexi_errors.NewWrappedError(err, "error evaluating custom gates")
			telemetry.SetSpanStatus(ctx, codes.Ok, "")
		} else {
			resultReason = telemetry.ReasonEvaluationFailed
			telemetry.RecordErrorToSpan(ctx, err)
			telemetry.SetSpanStatus(ctx, codes.Error, "")
		}
		return result, resultReason, err
	}

	result = isEnabled
	if isEnabled {
		resultReason = telemetry.ReasonCustomGate
		telemetry.SetSpanStatus(ctx, codes.Ok, "")
		return true, resultReason, nil
	}

	telemetry.SetSpanStatus(ctx, codes.Ok, "")
	return result, resultReason, nil
}

func anyActorInSegments(segments []*segment.Segment, actors []string) bool {
	for _, s := range segments {
		if s == nil {
			continue
		}
		for _, a := range actors {
			if s.Actors[a] {
				return true
			}
		}
	}
	return false
}
