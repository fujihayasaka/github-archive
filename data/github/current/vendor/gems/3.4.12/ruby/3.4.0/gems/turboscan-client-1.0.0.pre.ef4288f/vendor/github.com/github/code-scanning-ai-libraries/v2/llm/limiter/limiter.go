// Package limiter implements a rate-limiter that adapts to the behavior of the LLM backend.
package limiter

import (
	"context"
	"math"
	"sort"
	"sync"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/github-telemetry-go/kvp"
)

// WaitingCall represents a call that is currently waiting
type WaitingCall struct {
	StopTime     time.Time
	ResourceName string
	// updateCh is used to notify the waiting goroutine that its stop time changed
	updateCh chan time.Time
}

// ResourceLimiter manages rate limiting for named resources
type ResourceLimiter struct {
	mu sync.Mutex

	// Per-resource data
	results       map[string][]bool    // Last 100 results per resource (whether rate-limited or not)
	waitTimes     map[string]int       // Current wait time in milliseconds per resource
	lastStopTime  map[string]time.Time // Last stop time per resource (the time when the last call is scheduled to stop waiting)
	minimumStopAt map[string]time.Time // Minimum time at which any call can complete for this resource (e.g. if receiving a 429 with a specified retry-after, then we set `minimumStopAt` to that time). This is used instead of "now" for the waiting logic.

	// Global waiting queue
	waiting       map[int64]WaitingCall // Key is globally increasing counter
	nextWaitingID int64                 // Globally increasing counter
}

// globalLimiter is the singleton instance
var globalLimiter = &ResourceLimiter{
	results:       make(map[string][]bool),
	waitTimes:     make(map[string]int),
	lastStopTime:  make(map[string]time.Time),
	minimumStopAt: make(map[string]time.Time),
	waiting:       make(map[int64]WaitingCall),
}

const (
	// MaxIterations is the maximum number of iterations that should be attempted for a single request
	MaxIterations = 20

	minWaitTime                 = 20   // Minimum wait time in milliseconds
	maxWaitTime                 = 5000 // Maximum wait time in milliseconds
	defaultWaitTime             = 50   // Default wait time in milliseconds
	maxResults                  = 100  // Maximum number of results to keep per resource
	minResultsCheck             = 10   // Minimum results needed before adjusting wait time
	failureThreshold            = 0.05 // 5% failure rate threshold
	increaseFactorOnFailure     = 1.5
	decreaseMultiplierOnSuccess = 0.9
)

// DoWait waits synchronously until it's time to attempt calling the resource
func DoWait(name string) {
	globalLimiter.doWait(name)
}

// reportStatus records whether a call succeeded (true) or was rate-limited / failed (false).
func reportStatus(name string, success bool) {
	globalLimiter.reportSuccess(name, success)
}

// ReportSuccess records a successful call for the resource.
func ReportSuccess(name string) {
	reportStatus(name, true)
}

// ReportFailure records a rate-limited / failed call for the resource.
func ReportFailure(name string) {
	reportStatus(name, false)
}

// doWait implements the waiting logic for a named resource
func (rl *ResourceLimiter) doWait(name string) {
	rl.mu.Lock()

	// Initialize wait time if not exists
	if _, exists := rl.waitTimes[name]; !exists {
		rl.waitTimes[name] = defaultWaitTime
	}

	// Calculate when this call should stop waiting
	waitDuration := time.Duration(rl.waitTimes[name]) * time.Millisecond
	now := time.Now()

	// Find the time at which the last call for this resource will stop waiting
	maxStopTime := now
	if lastStop, exists := rl.lastStopTime[name]; exists {
		maxStopTime = lastStop // yes, this may be in the past, that's okay
	}

	// Apply minimum stop time if it's later than the calculated max stop time
	if minStopAt, exists := rl.minimumStopAt[name]; exists && minStopAt.After(maxStopTime) {
		maxStopTime = minStopAt
	}

	// New stop time is waitDuration after the max existing stop time
	stopTime := maxStopTime.Add(waitDuration)

	// If the stop time is in the past, set it to now (or minimum stop time if later)
	earliestAllowed := now
	if minStopAt, exists := rl.minimumStopAt[name]; exists && minStopAt.After(now) {
		earliestAllowed = minStopAt
	}
	if stopTime.Before(earliestAllowed) {
		stopTime = earliestAllowed
	}

	// Update the last stop time for this resource
	rl.lastStopTime[name] = stopTime

	// Add to waiting queue
	waitingID := rl.nextWaitingID
	rl.nextWaitingID++
	ch := make(chan time.Time, 1)
	rl.waiting[waitingID] = WaitingCall{
		StopTime:     stopTime,
		ResourceName: name,
		updateCh:     ch,
	}

	rl.mu.Unlock()

	// Ensure waiter is removed even on early exits
	defer func() {
		rl.mu.Lock()
		delete(rl.waiting, waitingID)
		rl.mu.Unlock()
	}()

	// Simple loop: compute remaining, wait on timer or updates
	current := stopTime
	timer := time.NewTimer(time.Until(current))
	defer func() {
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
	}()
	for {
		currentWaitTime := time.Until(current)
		if currentWaitTime <= 0 {
			break
		}
		resetTimer(timer, currentWaitTime)
		// Wait for either the timer to expire or an update to arrive through the channel
		select {
		case <-timer.C:
			// loop re-checks and exits if due
		case newStop := <-ch:
			current = newStop
		}
	}
}

// reportSuccess records the result and adjusts wait times if necessary
func (rl *ResourceLimiter) reportSuccess(name string, success bool) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	// Initialize results slice if not exists
	if _, exists := rl.results[name]; !exists {
		rl.results[name] = make([]bool, 0, maxResults)
	}

	// Add new result
	rl.results[name] = append(rl.results[name], success)

	// Keep only last 100 results
	if len(rl.results[name]) > maxResults {
		rl.results[name] = rl.results[name][len(rl.results[name])-maxResults:]
	}

	// Check if we need to adjust wait time
	rl.adjustWaitTimeIfNeeded(name, rl.results[name])
}

// adjustWaitTimeIfNeeded checks results and adjusts wait time if conditions are met
func (rl *ResourceLimiter) adjustWaitTimeIfNeeded(name string, results []bool) {
	if len(results) < minResultsCheck {
		return
	}

	// Initialize wait time if not exists
	if _, exists := rl.waitTimes[name]; !exists {
		rl.waitTimes[name] = defaultWaitTime
	}

	currentWaitTime := rl.waitTimes[name]
	newWaitTime := currentWaitTime

	// Evaluate recent performance across all collected results
	failures := 0
	for _, result := range results {
		if !result {
			failures++
		}
	}
	failureRate := float64(failures) / float64(len(results))

	// If failure rate is above threshold, slow down (increase wait time)
	if failureRate > failureThreshold {
		newWaitTime = min(maxWaitTime, int(float64(currentWaitTime)*increaseFactorOnFailure))
	} else if failures == 0 && len(results) > maxResults/4 { // only speed up if no failures, and enough results
		newWaitTime = max(minWaitTime, int(math.Round(float64(currentWaitTime)*decreaseMultiplierOnSuccess)))
	}

	if newWaitTime != currentWaitTime {
		rl.waitTimes[name] = newWaitTime
		// Whenever we do an adjustment, clear some more results so we don't reuse old results too much.
		// E.g. if we're constantly failing with the old wait time, but not with the new one, we want to clear old results.
		// Clear the 20 oldest results.
		if len(rl.results[name]) > 20 {
			rl.results[name] = rl.results[name][20:]
		} else if len(rl.results[name]) > 0 {
			// Less than 20, clear the list.
			rl.results[name] = make([]bool, 0, maxResults)
		}

		rl.recomputeWaitingTimes(name, newWaitTime-currentWaitTime)
	}
}

// recomputeWaitingTimes updates the stop times for all currently waiting calls for a resource
// diffTime is how much the waiting time was adjusted (positive for increased waiting time), which is used to adjust the first waiting call's stop time
func (rl *ResourceLimiter) recomputeWaitingTimes(name string, diffTime int) {
	newWaitDuration := time.Duration(rl.waitTimes[name]) * time.Millisecond
	now := time.Now()

	// Use minimum stop time if it's later than now
	baseTime := now
	if minStopAt, exists := rl.minimumStopAt[name]; exists && minStopAt.After(now) {
		baseTime = minStopAt
	}

	// Find all waiting calls for this resource, collect their IDs, and track the minimum (earliest) stop time
	var waitingIDs []int64
	var minStopTime time.Time
	for id, waitingCall := range rl.waiting {
		if waitingCall.ResourceName == name {
			waitingIDs = append(waitingIDs, id)
			if minStopTime.IsZero() || waitingCall.StopTime.Before(minStopTime) {
				minStopTime = waitingCall.StopTime
			}
		}
	}

	// Now, the baseTime is the maximum of `minStopAt`, `now`, and `minStopTime + diff` (the last because we want to account for the adjusted waiting time)
	if !minStopTime.IsZero() {
		adjusted := minStopTime.Add(time.Duration(diffTime) * time.Millisecond)
		if adjusted.After(baseTime) {
			baseTime = adjusted
		}
	}

	// Sort by waitingID to maintain order
	sort.Slice(waitingIDs, func(i, j int) bool { return waitingIDs[i] < waitingIDs[j] })

	// Recompute stop times with waitTime spacing between each, with the earliest being `baseTime`
	for i, id := range waitingIDs {
		newStopTime := baseTime.Add(time.Duration(i) * newWaitDuration)
		wc := rl.waiting[id]
		wc.StopTime = newStopTime
		rl.waiting[id] = wc
		trySendUpdate(wc.updateCh, newStopTime)
	}

	// Update the last stop time for this resource
	if len(waitingIDs) > 0 {
		rl.lastStopTime[name] = baseTime.Add(time.Duration(len(waitingIDs)) * newWaitDuration)
	}
}

// GetWaitTime returns the current wait time for a resource (for testing/debugging)
func GetWaitTime(name string) int {
	return globalLimiter.getWaitTime(name)
}

func (rl *ResourceLimiter) getWaitTime(name string) int {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	if waitTime, exists := rl.waitTimes[name]; exists {
		return waitTime
	}
	return defaultWaitTime
}

// GetResultsCount returns the number of results stored for a resource (for testing/debugging)
func GetResultsCount(name string) int {
	return globalLimiter.getResultsCount(name)
}

func (rl *ResourceLimiter) getResultsCount(name string) int {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	if results, exists := rl.results[name]; exists {
		return len(results)
	}
	return 0
}

// setMinimumStopTime sets the minimum time before any call can complete for a resource
func (rl *ResourceLimiter) setMinimumStopTime(name string, minTime time.Time) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	rl.minimumStopAt[name] = minTime
	rl.recomputeWaitingTimes(name, 0)
}

// resetTimer safely stops, drains, and resets the timer to the given duration
func resetTimer(t *time.Timer, d time.Duration) {
	if !t.Stop() {
		select {
		case <-t.C:
		default:
		}
	}
	t.Reset(d)
}

// trySendUpdate attempts to send a stop time update, replacing any stale value in the buffer
func trySendUpdate(ch chan time.Time, newStopTime time.Time) {
	select {
	case ch <- newStopTime:
		return
	default:
		// buffer full; drop stale and try once more
	}
	select {
	case <-ch:
	default:
	}
	select {
	case ch <- newStopTime:
	default:
	}
}

// RetryFunction represents a function that can be retried
type RetryFunction[T any] func() (T, errors.LLMError)

// WithRetry executes a function with retry logic and rate limiting
// If retry is false, the function is executed once without rate limiting
// If retry is true, the function is executed with rate limiting and retry logic
func WithRetry[T any](ctx context.Context, resourceName string, retry bool, fn RetryFunction[T]) (T, errors.LLMError) {
	if !retry {
		return fn()
	}

	var result T
	var llmErr errors.LLMError

	for iteration := range MaxIterations {
		DoWait(resourceName)

		result, llmErr = fn()
		if llmErr != nil && errors.IsRetryableError(llmErr) {
			ReportFailure(resourceName)
			if iteration < MaxIterations-1 {
				// If we are not on the last iteration, continue to retry
				enhancedctx.Logger(ctx).WithError(llmErr).Debug(
					"Retrying request due to retryable error",
					kvp.Int("iteration", iteration+1),
				)

				// Set minimum stop time based on retry delay (if any)
				retryDelay := llmErr.RetryDelay()
				if retryDelay > 0 {
					minStopTime := time.Now().Add(retryDelay)
					enhancedctx.Logger(ctx).Debug(
						"Setting minimum stop time for retry delay",
						kvp.String("delay", retryDelay.String()),
						kvp.String("minStopTime", minStopTime.Format(time.RFC3339Nano)),
					)
					globalLimiter.setMinimumStopTime(resourceName, minStopTime)
				}

				continue // not the last iteration, so we retry
			}
			break // last iteration, continue with the error.
		}

		ReportSuccess(resourceName) // Not a retry, report success.
		break
	}

	return result, llmErr
}
