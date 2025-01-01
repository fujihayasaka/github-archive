package observability

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

type checkpointKey string

// AqJobSentAtCheckpoint indicates when the job was enqueued
// The key name is also used as a field name for logging, hence the snake case
var AqJobSentAtCheckpoint checkpointKey = "aqueduct_job_sent_at"

// AqJobRecvAtCheckpoint indicates when the job was dequeued
var AqJobRecvAtCheckpoint checkpointKey = "aqueduct_job_received_at"

// AqJobOrigRecvAtCheckpoint indicates when the original job was dequeued
var AqOrigJobRecvAtCheckpoint checkpointKey = "orig_aqueduct_job_received_at"

// PRMergeCommitResolvedAtCheckpoint indicates when the merge commit was resolved for a pull request event
var PRMergeCommitResolvedAtCheckpoint checkpointKey = "pr_merge_commit_resolved_at"

var jobCheckpointKeys = []checkpointKey{
	AqJobSentAtCheckpoint,
	AqJobRecvAtCheckpoint,
	AqOrigJobRecvAtCheckpoint,
	// The aqueduct job can be rescheduled multiple times to continue polling for a merge commit
	PRMergeCommitResolvedAtCheckpoint,
}

// ExchangeURLCheckpoint is used to mark the start of obtaining a signed URL
var ExchangeURLCheckpoint checkpointKey = "obs.exchangeURL"

// DeleteArtifactCheckpoint is used to mark the start of deleting an artifact.
var DeleteArtifactCheckpoint checkpointKey = "obs.deleteArtifact"

// EventOriginTime is the time when the origin was originally instrumented
var EventOriginTime checkpointKey = "obs.eventOriginTime"

var TwirpRequestCheckpoint checkpointKey = "obs.twirpRequest"

// CreateGitHubTokenCheckpoint can be used for creating an access token for
// communicating with GitHub”s API.
var CreateGitHubTokenCheckpoint checkpointKey = "obs.createToken"

// AuthenticateRequestCheckpoint can be used for an authentication for getting a
// bearer token.
var AuthenticateRequestCheckpoint checkpointKey = "obs.authenticateRequest"

// AuthenticateAsServicePrincipalCheckpoint can be used for authentication via
// the service principal.
var AuthenticateAsServicePrincipalCheckpoint checkpointKey = "obs.authenticateAsServicePrincipal"

// PurgeTokenCacheCheckpoint is for timing how long the token purge takes
var PurgeTokenCacheCheckpoint checkpointKey = "obs.purgeToken"

// KeyVaultRequestCheckpoint can be used for calls to the azure key vault
var KeyVaultRequestCheckpoint checkpointKey = "obs.keyVaultRequest"

// CredzRPCRequestCheckpoint can be used for requests to credz
var CredzRPCRequestCheckpoint checkpointKey = "obs.credzRequest"

// DeleteBuildLogsCheckpoint is used to mark the start of deleting an artifact.
var DeleteBuildLogsCheckpoint checkpointKey = "obs.deleteBuildLogs"

// PurgeTTLCacheCheckpoint is used to indicate how long it took to purge items from the cache
var PurgeTTLCacheCheckpoint checkpointKey = "obs.ttlCachePurge"

// NotifyGateCheckpoint is used to mark the start of notifying actions service a
// gate conclusion has been updated.
var NotifyGateCheckpoint checkpointKey = "obs.notifyGate"

// Observability is a struct for logging, sending stats, and measuring time between checkpoints
type Observability struct {
	logger.Logger
	statter.Statter
	checkpoints *sync.Map
}

// New returns a pointer to a new `Observability` struct
func New(logger logger.Logger, statter statter.Statter) *Observability {
	return &Observability{
		logger,
		statter,
		new(sync.Map),
	}
}

func CopyCheckpoints(obs *Observability) *Observability {
	pts := new(sync.Map)
	obs.checkpoints.Range(func(k, v any) bool {
		pts.Store(k, v)
		return true
	})

	return &Observability{
		obs.Logger,
		obs.Statter,
		pts,
	}
}

// AddCheckpoint adds a checkpoint with an arbitrary time
func (o *Observability) AddCheckpoint(key checkpointKey, time time.Time) {
	o.checkpoints.Store(key, time)
}

// StartCheckpoint sets the start time for a given check point to the current time
func (o *Observability) StartCheckpoint(key checkpointKey) {
	o.checkpoints.Store(key, time.Now())
}

// GetCheckpointTime returns a checkpoint's time
func (o *Observability) GetCheckpointTime(key checkpointKey) (time.Time, bool, error) {
	t, ok := o.checkpoints.Load(key)
	if !ok {
		return time.Time{}, ok, nil
	}

	switch t := t.(type) {
	case time.Time:
		return t, ok, nil
	default:
		return time.Time{}, ok, NewInvalidKeyError(string(key))
	}
}

// GetCheckpointAqJobFields returns the set aqueduct job checkpoints as logging fields
func (o *Observability) GetCheckpointAqJobFields(ctx context.Context) []kvp.Field {
	var fields []kvp.Field

	for _, key := range jobCheckpointKeys {
		t, ok, err := o.GetCheckpointTime(key)
		if err != nil {
			o.ErrorWithFields(ctx, "can't retrieve job checkpoint time", err, kvp.String("gh.launch.checkpoint_key", string(key)))
			return []kvp.Field{}
		}
		if ok {
			fieldName := string(key)
			fields = append(fields, kvp.Time(fieldName, t))
		}
	}

	return fields
}

// LogDuration logs the duration since the given time key
func (o *Observability) LogDuration(ctx context.Context, timeSinceKey checkpointKey, key string, threshold time.Duration, tags statter.Tags) (time.Duration, error) {
	duration, err := o.getDuration(timeSinceKey)
	if err != nil {
		return 0, err
	}

	return o.logDuration(ctx, key, duration, threshold, tags)
}

// LogDurationWithoutCheckpoint logs the duration since the given time, without requiring a checkpoint
func (o *Observability) LogDurationWithoutCheckpoint(ctx context.Context, key string, startTime time.Time, threshold time.Duration, tags statter.Tags) (time.Duration, error) {
	duration := time.Since(startTime)

	return o.logDuration(ctx, key, duration, threshold, tags)
}

func (o *Observability) logDuration(ctx context.Context, key string, duration, threshold time.Duration, tags statter.Tags) (time.Duration, error) {
	withinThreshold := duration < threshold
	if !withinThreshold {
		o.Debug(ctx, "operation took too long to run", kvp.Duration("gh.launch.duration_sec", duration), kvp.String("gh.launch.operation.name", key))
	}

	tags = tags.Merge(statter.Tags{"within_threshold": strconv.FormatBool(withinThreshold)})

	o.LegacyTiming(ctx, key, tags, duration)
	return duration, nil
}

// LogDurationWithoutThreshold logs the duration since the given time key without any threshold calculation
func (o *Observability) LogDurationWithoutThreshold(ctx context.Context, timeSinceKey checkpointKey, key string, tags statter.Tags) (time.Duration, error) {
	duration, err := o.getDuration(timeSinceKey)
	if err != nil {
		return 0, err
	}

	o.LegacyTiming(ctx, key, tags, duration)
	return duration, nil
}

func (o *Observability) getDuration(key checkpointKey) (time.Duration, error) {
	var duration time.Duration
	t, ok, err := o.GetCheckpointTime(key)
	if err != nil {
		return duration, err
	}
	if !ok {
		return duration, NewMissingKeyError(string(key))
	}

	return time.Since(t), nil
}

// MonitorCircuitBreaker starts up monitors for the circuit breaker via the statter and logger.
func MonitorCircuitBreaker(ctx context.Context, obs *Observability, name string, breaker *circuit.Breaker) {
	logger.MonitorCircuitBreaker(ctx, obs.Logger, name, breaker)
	statter.MonitorCircuitBreaker(ctx, obs.Statter, name, breaker)
}

// NewNullObservability creates a new `Observability` using null loggers and statters
func NewNullObservability() *Observability {
	return New(logger.NullLogger(), statter.NullStatter())
}

// NewTestObservability creates a new `Observability` using test loggers and statters
func NewTestObservability() *Observability {
	return New(logger.TestLogger(), statter.NullStatter())
}

// NewMockedObservability creates a new `Observability` using mocked Logger and Statter interfaces
func NewMockedObservability() (*Observability, *logger.MockLogger, *statter.MockStatter) {
	logger := &logger.MockLogger{}
	statter := &statter.MockStatter{}
	return New(logger, statter), logger, statter
}

// MissingKeyError happens if one attempts to read a key from the key map that isn't present
type MissingKeyError struct {
	key string
}

// NewMissingKeyError creates a new MissingKeyError
func NewMissingKeyError(key string) *MissingKeyError {
	return &MissingKeyError{key}
}

func (e MissingKeyError) Error() string {
	return fmt.Sprintf("Missing value for observability key %q", e.key)
}

// InvalidKeyError happens if a non-time.Time value ends up in the key map
type InvalidKeyError struct {
	key string
}

// NewInvalidKeyError creates a new InvalidKeyError
func NewInvalidKeyError(key string) *InvalidKeyError {
	return &InvalidKeyError{key}
}

func (e InvalidKeyError) Error() string {
	return fmt.Sprintf("Invalid value for observability key %q", e.key)
}
