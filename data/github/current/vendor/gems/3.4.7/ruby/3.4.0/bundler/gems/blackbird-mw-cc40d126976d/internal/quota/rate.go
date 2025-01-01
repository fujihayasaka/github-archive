package quota

import (
	"context"
	_ "embed"
	"fmt"
	"math"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/pkg/errors"
)

type QuotaResult = string

const (
	QuotaOk                  QuotaResult = "ok"
	QuotaShortViolation      QuotaResult = "reject-short"
	QuotaLongViolation       QuotaResult = "reject-long"
	QuotaZeroQuotaExperiment QuotaResult = "zero-quota"
	QuotaError               QuotaResult = "error"
)

// RateEstimate is the result of requesting a rate estimate for an actor.
type RateEstimate struct {
	// Quota key, for later use.
	key Key
	// Server timestamp, for later use.
	timestamp float64
	// Amount (cost) pre-charged, for later use.
	PreCharge float64
	// Estimated usage rate (cost/second) over the past ~10 seconds
	ShortTermRate float64
	// Estimated usage rate (cost/second) over the past ~12 hours
	LongTermRate float64
}

func NewRateEstimate(key Key, timestamp, preCharge, shortTermRate, longTermRate float64) *RateEstimate {
	return &RateEstimate{
		key:           key,
		timestamp:     timestamp,
		PreCharge:     preCharge,
		ShortTermRate: shortTermRate,
		LongTermRate:  longTermRate,
	}
}

func decayTime(current, target, halfLife float64) float64 {
	if current <= target {
		return 0.0
	}
	return math.Log2(current/target) * halfLife
}

// Returns the amount of time, in seconds, from `e.timestamp` until the actor
// is out of quota violation, assuming they leave us alone that long. Returns 0
// if they're already not in violation.
func (e *RateEstimate) BanTime(shortTermRateLimit, longTermRateLimit int) float64 {
	return math.Max(
		decayTime(e.ShortTermRate, float64(shortTermRateLimit), shortTermHalfLifeSeconds),
		decayTime(e.LongTermRate, float64(longTermRateLimit), longTermHalfLifeSeconds))
}

// Time returns the time when this rate estimate was calculated.
func (e *RateEstimate) Time() time.Time {
	seconds, fraction := math.Modf(e.timestamp)
	return time.Unix(int64(seconds), int64(fraction*1e9))
}

// RateEstimator stores estimates of each actor's current usage rates, and
// checks whether they are in violation of our rate limits.
type RateEstimator interface {
	// Pre-query operation: If the given actor is not currently in violation of
	// either the short- or long-term rate limits, charge the approximate cost
	// of a query to them.  If the actor IS in violation, the pre-charge is NOT
	// applied.  Returns their current estimated usage rates regardless.
	//
	// This can be used to ask for an actor's current estimated usage rate,
	// by passing preCharge=0.
	PreQueryCharge(ctx context.Context, key Key, preCharge float64, shortTermRateLimit, longTermRateLimit int) (QuotaResult, *RateEstimate, error)

	// Post-query operation: Undo the charge done by PreQueryCharge, and
	// instead charge the actual `cost` of the query.
	PostQueryAdjust(ctx context.Context, key Key, startTime float64, preCharge float64, cost float64) error

	// Reset an actor's usage rates to 0.
	ResetRates(ctx context.Context, key Key) error
}

// RedisRateEstimator is a RateEstimator implementation using Redis as the backing store.
type RedisRateEstimator struct {
	client             *redis.Client
	preQueryScriptSHA  string
	postQueryScriptSHA string

	// If this is zero (the default), we will use the Redis server's actual
	// clock to generate timestamps.  If nonzero (via SimulateClock), then we
	// will use a simulated clock, passing the current simulated time into the
	// Lua script.
	simulatedTime float64
}

func NewRedisRateEstimator(ctx context.Context, client *redis.Client) (*RedisRateEstimator, error) {
	est := &RedisRateEstimator{client: client}
	if err := est.loadScripts(ctx); err != nil {
		return nil, err
	}
	return est, nil
}

func (c *RedisRateEstimator) loadScripts(ctx context.Context) error {
	cmd := c.client.ScriptLoad(ctx, redisPreQueryScript)
	preQueryScriptSHA, err := cmd.Result()
	if err != nil {
		return errors.Wrap(err, "error loading pre query rate estimator script into Redis")
	}
	c.preQueryScriptSHA = preQueryScriptSHA

	cmd = c.client.ScriptLoad(ctx, redisPostQueryScript)
	postQueryScriptSHA, err := cmd.Result()
	if err != nil {
		return errors.Wrap(err, "error loading post query rate estimator script into Redis")
	}
	c.postQueryScriptSHA = postQueryScriptSHA

	return nil
}

func (c *RedisRateEstimator) SimulateClock(ctx context.Context) {
	if c.simulatedTime != 0 {
		panic("simulated Redis clock already initialized")
	}
	c.simulatedTime = float64(time.Now().Unix())
}

func (c *RedisRateEstimator) AdvanceClock(ctx context.Context, seconds float64) {
	if c.simulatedTime == 0 {
		panic("did not initialize simulated Redis clock")
	}
	c.simulatedTime += seconds
}

func (c *RedisRateEstimator) PreQueryCharge(ctx context.Context, key Key, preCharge float64, shortTermRateLimit, longTermRateLimit int) (QuotaResult, *RateEstimate, error) {
	cmdOp := func() *redis.Cmd {
		return c.client.EvalSha(
			ctx, c.preQueryScriptSHA,
			[]string{key.String()},
			preCharge, c.simulatedTime,
			shortTermHalfLifeSeconds, shortTermRateLimit,
			longTermHalfLifeSeconds, longTermRateLimit,
		)
	}
	resultStr, err := c.doCmd(ctx, cmdOp)
	if err != nil {
		return QuotaError, nil, errors.Wrap(err, "failed to bump actor usage rate in Redis")
	}

	// Parse the results. Redis returns a string. See earrrl.lua.
	fields := strings.Split(resultStr, " ")
	if len(fields) != 5 {
		return QuotaError, nil, errors.Wrapf(err, "malformed result from Redis: %q", resultStr)
	}
	result := QuotaResult(fields[0])
	timestamp, err := strconv.ParseFloat(fields[1], 64)
	if err != nil {
		return QuotaError, nil, errors.Wrapf(err, "malformed result from Redis: %q", resultStr)
	}
	chargeApplied, err := strconv.ParseFloat(fields[2], 64)
	if err != nil {
		return QuotaError, nil, errors.Wrapf(err, "malformed result from Redis: %q", resultStr)
	}
	shortTermRate, err := strconv.ParseFloat(fields[3], 64)
	if err != nil {
		return QuotaError, nil, errors.Wrapf(err, "malformed result from Redis: %q", resultStr)
	}
	longTermRate, err := strconv.ParseFloat(fields[4], 64)
	if err != nil {
		return QuotaError, nil, errors.Wrapf(err, "malformed result from Redis: %q", resultStr)
	}
	rates := &RateEstimate{
		key:           key,
		timestamp:     timestamp,
		PreCharge:     chargeApplied,
		ShortTermRate: shortTermRate,
		LongTermRate:  longTermRate,
	}
	return result, rates, nil
}

func (c *RedisRateEstimator) PostQueryAdjust(ctx context.Context, key Key, startTime float64, preCharge float64, cost float64) error {
	cmdOp := func() *redis.Cmd {
		return c.client.EvalSha(
			ctx, c.postQueryScriptSHA,
			[]string{key.String()},
			startTime, preCharge, cost, c.simulatedTime,
			shortTermHalfLifeSeconds, longTermHalfLifeSeconds,
		)
	}
	val, err := c.doCmd(ctx, cmdOp)
	if err != nil {
		return errors.Wrap(err, "failed to adjust actor usage rate in Redis")
	}
	if val != "ok" {
		return errors.Errorf("failed to adjust actor usage rate: unexpected result from Redis: %q", val)
	}
	return nil
}

// doCmd is a helper that runs a Redis command and conditionally reloads lua scripts as needed.
func (c *RedisRateEstimator) doCmd(ctx context.Context, cmdOp func() *redis.Cmd) (string, error) {
	cmd := cmdOp()
	val, err := cmd.Text()
	if err != nil {
		if strings.Contains(err.Error(), "NOSCRIPT No matching script") {
			loadErr := c.loadScripts(ctx)
			if loadErr != nil {
				return "", fmt.Errorf("cmd error: %w / load script error: %w", err, loadErr)
			}

			// Retry the command.
			cmd = cmdOp()
			val, err = cmd.Text()
		}
	}

	return val, err
}

func (c *RedisRateEstimator) ResetRates(ctx context.Context, key Key) error {
	cmd := c.client.Del(ctx, fmt.Sprintf("usage.%s.short", key), fmt.Sprintf("usage.%s.long", key))
	_, err := cmd.Result()
	if err != nil {
		return errors.Wrap(err, "failed to reset actor usage rate in Redis")
	}
	return nil
}

// MemoryRateEstimator is a RateEstimator implementation using an in-memory map.
type MemoryRateEstimator struct {
	mutex       sync.Mutex
	now         float64
	m           map[Key]*ActorState
	autoAdvance float64
}

type ActorState struct {
	shortTerm        *Earrrl
	longTerm         *Earrrl
	totalCostCharged float64
}

type Earrrl struct {
	rate      float64
	timestamp float64
}

func NewMemoryRateEstimator() *MemoryRateEstimator {
	// `timestamp: 0` has a special meaning to PostQuery, so start the fake clock at 1.
	return &MemoryRateEstimator{
		mutex:       sync.Mutex{},
		now:         1.0,
		m:           make(map[Key]*ActorState),
		autoAdvance: 0.0,
	}
}

func (c *MemoryRateEstimator) GetTotalCostCharged(ctx context.Context, key Key) float64 {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	return c.m[key].totalCostCharged
}

func (c *MemoryRateEstimator) PreQueryCharge(ctx context.Context, key Key, preCharge float64, shortTermRateLimit, longTermRateLimit int) (QuotaResult, *RateEstimate, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	actorState, exists := c.m[key]
	if !exists {
		actorState = &ActorState{shortTerm: &Earrrl{}, longTerm: &Earrrl{}}
		c.m[key] = actorState
	}

	shortTermOldRate, shortTermNewRate := actorState.shortTerm.CalculateCharge(shortTermHalfLifeSeconds, c.now, preCharge)
	longTermOldRate, longTermNewRate := actorState.longTerm.CalculateCharge(longTermHalfLifeSeconds, c.now, preCharge)
	rates := &RateEstimate{
		key:           key,
		timestamp:     c.now,
		PreCharge:     preCharge,
		ShortTermRate: shortTermOldRate,
		LongTermRate:  longTermOldRate,
	}

	// Determine whether the user was already in violation.
	result := QuotaOk
	if shortTermOldRate > float64(shortTermRateLimit) {
		result = QuotaShortViolation
	} else if longTermOldRate > float64(longTermRateLimit) {
		result = QuotaLongViolation
	}

	// Update the state for this query bucket, but do NOT apply the pre-charge
	// if the user was in violation.  (We still need to update the state to
	// advance forward to the current time and credit any rate decay that has
	// occurred.)
	if result == QuotaOk {
		actorState.shortTerm.Set(c.now, shortTermNewRate)
		actorState.longTerm.Set(c.now, longTermNewRate)
	} else {
		// We could update our state to hold `oldRate` here, but it won't change
		// the results of this or any future rate limit checks, so we skip that
		// to be consistent with what we're doing in the Redis Lua script.
		rates.PreCharge = 0
	}
	actorState.totalCostCharged += preCharge

	c.now += c.autoAdvance
	c.autoAdvance = 0

	return result, rates, nil
}

func (c *MemoryRateEstimator) PostQueryAdjust(ctx context.Context, key Key, startTime float64, preCharge float64, cost float64) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.m[key].shortTerm.Adjust(shortTermHalfLifeSeconds, startTime, preCharge, c.now, cost)
	c.m[key].longTerm.Adjust(longTermHalfLifeSeconds, startTime, preCharge, c.now, cost)
	c.m[key].totalCostCharged -= (preCharge - cost)
	return nil
}

func (c *MemoryRateEstimator) ResetRates(ctx context.Context, key Key) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	delete(c.m, key)
	return nil
}

func (c *MemoryRateEstimator) SimulateClock(ctx context.Context) {
}

func (c *MemoryRateEstimator) AdvanceClock(ctx context.Context, seconds float64) {
	c.now += seconds
}

// SetAutoAdvance configures the clock to jump ahead by the given amount the
// next time PreQueryCharge is called. It's a way to make it look (to the quota
// system) as if the query took this long to run on the shards.
func (c *MemoryRateEstimator) SetAutoAdvance(seconds float64) {
	c.autoAdvance = seconds
}

// Calculates the current rate as of `tNow`, both before and after a pre-charge
// of `charge` is applied.  Does not update the state for this quota bucket.
func (e *Earrrl) CalculateCharge(halfLifeSeconds float64, tNow float64, charge float64) (float64, float64) {
	// Closely following the script (redis_pre_query.lua).
	lambda := math.Log(2.0) / halfLifeSeconds
	oldRate := e.rate * math.Exp(-lambda*(tNow-e.timestamp))
	newRate := oldRate + lambda*charge
	return oldRate, newRate
}

func (e *Earrrl) Set(tNow float64, rate float64) {
	e.rate = rate
	e.timestamp = tNow
}

func (e *Earrrl) Adjust(halfLifeSeconds float64, tThen float64, chargeThen float64, tNow float64, chargeNow float64) {
	// First bring our rate estimate up to the present.
	lambda := math.Log(2.0) / halfLifeSeconds
	e.rate *= math.Exp(-lambda * (tNow - e.timestamp))

	// Compute adjusted rate by subtracting the old charge and adding the new one.
	// Closely following the script (redis_post_query.lua).
	decay := math.Exp(-lambda * (tNow - tThen))
	adjustment := chargeNow - chargeThen*decay
	e.rate += lambda * adjustment
	e.timestamp = tNow
}

//go:embed redis_pre_query.lua
var redisPreQueryScript string

//go:embed redis_post_query.lua
var redisPostQueryScript string
