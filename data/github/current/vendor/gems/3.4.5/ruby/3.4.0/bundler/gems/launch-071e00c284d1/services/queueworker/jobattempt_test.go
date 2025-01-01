package queueworker

import (
	"math/rand"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/constraints"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/utils/clock"
	"github.com/github/launch/utils/mathutils"
	"github.com/github/launch/utils/timeutils"
)

func Test_extractAttemptDetails_InitialAttempt(t *testing.T) {
	mc := clock.NewMock(100)

	aqueductJobId := "aq-job-123"
	rr := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID: aqueductJobId,
		},
	}

	ja, err := extractAttemptDetails(rr, mc.Now())
	require.NoError(t, err)
	require.NotNil(t, ja)
	// Attempt number is 1-based (not zero-based).
	assert.Equal(t, uint(1), ja.attemptNumber)
	assert.Equal(t, aqueductJobId, ja.originalAqueductJobID)
	assert.Equal(t, mc.Now(), ja.originalReceiveAt)
	assert.False(t, ja.isRetry())
	assert.True(t, ja.retryUntil.After(mc.Now()))
}

func Test_add_and_extract(t *testing.T) {
	mc := clock.NewMock(100)
	startTime := mc.Now().Add(-4 * time.Minute)
	soon := mc.Now().Add(15 * time.Second)
	later := mc.Now().Add(180 * time.Second)

	cases := []struct {
		name          string
		attemptNumber uint
		retryUntil    time.Time
		finalAttempt  bool
	}{
		{
			name:          "Intermediate attempt",
			attemptNumber: 3,
			retryUntil:    later,
			finalAttempt:  false,
		},
		{
			name:          "Final attempt",
			attemptNumber: 5,
			retryUntil:    soon,
			finalAttempt:  true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			origAqueductJobId := "aq-job-123"

			sendJa := &jobAttempt{
				attemptNumber:         tc.attemptNumber,
				originalAqueductJobID: origAqueductJobId,
				originalReceiveAt:     startTime,
				retryUntil:            tc.retryUntil,
			}

			nextAttemptJob := &aqueduct.Job{}
			sendJa.addAttemptDetails(nextAttemptJob)

			// addAttemptDetails shouldn't set the job id
			assert.Empty(t, nextAttemptJob.ID)

			// Sometime later this job will be received.
			nextAttemptJob.ID = "aq-job-456"
			rr := &aqueduct.ReceiveResult{
				Job: *nextAttemptJob,
			}

			ja, err := extractAttemptDetails(rr, mc.Now())
			require.NoError(t, err)
			require.NotNil(t, ja)
			assert.Equal(t, tc.attemptNumber, ja.attemptNumber)
			assert.Equal(t, origAqueductJobId, ja.originalAqueductJobID)
			assert.Equal(t, startTime, ja.originalReceiveAt)
			assert.True(t, ja.isRetry())
		})
	}
}

func Test_possiblyExtendRetryWindow_attemptsRemaining(t *testing.T) {
	mc := clock.NewMock(100)

	// starting off with a 5 minute retry window
	fourMinutesAgo := mc.Now().Add(-4 * time.Minute)
	oneMinuteFromNow := mc.Now().Add(time.Minute)

	ja := &jobAttempt{
		attemptNumber:         5,
		originalAqueductJobID: "aq-job-123",
		originalReceiveAt:     fourMinutesAgo,
		retryUntil:            oneMinuteFromNow,
	}

	assert.False(t, ja.possiblyExtendRetryWindow(4*time.Minute)) // already five minutes
	assert.False(t, ja.possiblyExtendRetryWindow(5*time.Minute)) // already five minutes
	assert.True(t, ja.possiblyExtendRetryWindow(6*time.Minute))
	assert.True(t, ja.possiblyExtendRetryWindow(7*time.Minute))
	assert.True(t, ja.possiblyExtendRetryWindow(8*time.Minute))
	assert.False(t, ja.possiblyExtendRetryWindow(8*time.Minute)) // already 8 minutes
	assert.False(t, ja.possiblyExtendRetryWindow(7*time.Minute)) // already 8 minutes
}

func Test_overall_job_time(t *testing.T) {
	// The p95 for processing expensive jobs like merge commit is about 15 seconds.
	// (see https://app.datadoghq.com/notebook/8784908/actions-cprmc?cell_id=8wull9yi&from_ts=1719589332445&to_ts=1719607013776#launch-merge-commit-resolved-at)
	p95JobDuration := 15 * time.Second

	reps := 3000
	// stores cumulative duration for each attempt
	// Example:
	// 0:  [15.0, 15.0, 15.0, ...]
	// 1:  [105.0, 104.0, 106.9, ...]
	// 2:  [240.0, 235.0, 245.9, ...]
	timings := map[uint][]time.Duration{}

	for j := 0; j < reps; j++ {
		cumulativeDuration := 0 * time.Second
		// simulate several more attempts than we actually expect to see in production
		for attempt := uint(0); attempt < 10; attempt++ {
			// ComputeBackoff expects a one-based attempt number.
			backoff := ComputeBackoff(attempt + 1)

			// simulate the job taking some time to process after the backoff period elapses
			cumulativeDuration += (backoff + p95JobDuration)
			timings[attempt] = append(timings[attempt], cumulativeDuration)
		}
	}

	onePercent := reps / 100

	// Verify that 100% of the inital attempts were not subject to any backoff delay.
	assert.Equal(t, reps, countLessThanOrEqualTo(timings[0], p95JobDuration))

	// Verify that at least 90% of the time, we were able to complete 2 attempts (inital attempt + 1 retry) (and likely queue an additional attempt) within the default retry window.
	assert.GreaterOrEqual(t, countLessThanOrEqualTo(timings[1], defaultMaxRetryWindow), 90*onePercent)

	// For the case that the retry window is extended,
	// Verify that at least 90% of the time, we were able to complete 3 attempts (inital attempt + 2 retries) (and likely queue an additional attempt) within the extended retry window.
	assert.GreaterOrEqual(t, countLessThanOrEqualTo(timings[2], workflowinvoker.ErrMergeableCommitTimeout.RetryDuration()), 90*onePercent)

	// For the case that the retry window is extended,
	// Verify that at least 75% of the time, we were able to complete 4 attempts (inital attempt + 3 retries) (and likely queue an additional attempt) within the extended retry window.
	assert.GreaterOrEqual(t, countLessThanOrEqualTo(timings[3], workflowinvoker.ErrMergeableCommitTimeout.RetryDuration()), 75*onePercent)

	// For the case that the retry window is extended,
	// Verify that at least 15% of the time, we were able to complete 5 attempts (inital attempt + 4 retries) (and likely queue an additional attempt) within the extended retry window.
	assert.GreaterOrEqual(t, countLessThanOrEqualTo(timings[4], workflowinvoker.ErrMergeableCommitTimeout.RetryDuration()), 15*onePercent)
}

// Test how many times jobs with retryable errors are attempted. While job retries are duration based, we don't want
// the number of job attempts to be too few or too many. Too few retries and we won't overcome transient errors and
// hit our SLO targets (three nines for actions/availability/queue-run). Too many retries and we'll add undue load to
// our dependencies when they're unhealthy.
func Test_number_of_job_attempts(t *testing.T) {
	r := rand.New(rand.NewSource(42))

	reps := 3000
	recordings := 0
	hgram := map[uint]int{}

	for i := 0; i < reps; i++ {
		mc := clock.NewMock(100)

		job := aqueduct.Job{}
		for expectedAttempt := uint(1); ; expectedAttempt++ {
			rr := &aqueduct.ReceiveResult{
				Job: job,
			}

			ja, err := extractAttemptDetails(rr, mc.Now())
			require.NoError(t, err)
			assert.Equal(t, expectedAttempt, ja.attemptNumber)

			// Jobs attempts can take 60+ seconds if there's an http response timeout.
			processTime := timeutils.ScaleDuration(mathutils.RandomFloat64(r, 0, 75), time.Second)
			mc.Add(processTime)

			backoff := ComputeBackoff(ja.attemptNumber)
			isFinalAttempt := mc.Now().Add(backoff).After(ja.retryUntil)
			if isFinalAttempt {
				hgram[ja.attemptNumber]++
				recordings++
				break
			}

			// simulate the next aqueduct payload arriving
			job = aqueduct.Job{}
			ja.attemptNumber++
			ja.addAttemptDetails(&job)
			mc.Add(backoff)
		}
	}

	assert.Equal(t, reps, recordings)

	// Expected: Jobs with retryable errors are attempted 2-4 times (no less and no more, ignoring RetryableDurationErrors),
	// with 3 attempts being by far the most common.
	assert.Equal(t, 3, len(hgram))
	assert.ElementsMatch(t, []uint{2, 3, 4}, extractKeys(hgram))
	assert.Greater(t, hgram[3], 5*hgram[2])
	assert.Greater(t, hgram[3], 5*hgram[4])
}

func Test_getTimeHeader_empty(t *testing.T) {
	job := &aqueduct.Job{}

	time, ok, err := getTimeHeader(job, "foo")
	require.NoError(t, err)
	assert.Zero(t, time)
	assert.False(t, ok)
}

func Test_setTimeHeader_getTimeHeader(t *testing.T) {
	job := &aqueduct.Job{}
	ot := time.Date(2019, 1, 1, 0, 0, 0, 0, time.UTC)

	setTimeHeader(job, "foo", ot)

	time, ok, err := getTimeHeader(job, "foo")
	require.NoError(t, err)
	assert.Equal(t, ot, time)
	assert.True(t, ok)

	time, ok, err = getTimeHeader(job, "bar")
	require.NoError(t, err)
	assert.Zero(t, time)
	assert.False(t, ok)
}

func extractKeys[K comparable, V any](m map[K]V) []K {
	keys := make([]K, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

func countLessThanOrEqualTo[T constraints.Ordered](members []T, threshold T) int {
	count := 0
	for _, m := range members {
		if m <= threshold {
			count++
		}
	}
	return count
}
