package queueworker

import (
	"fmt"
	"strconv"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/mathutils"
	"github.com/github/launch/utils/timeutils"
)

const (
	// N.B. Attempt numbers are 1 based.
	headerOriginalAqueductJobID = "x-launch-original-aqueduct-job-id"
	headerJobAttempt            = "x-launch-job-attempt"
	headerOriginalReceiveTime   = "x-launch-original-receive-time"
	headerFinalAttemptTime      = "x-launch-final-attempt-time"

	// Goal: 3-4 job attempts in 4 minutes (including the initial attempt)
	//       or 4-5 job attempts in 10 minutes (when the retry window gets extended).
	// See unit tests: Test_number_of_job_attempts.
	defaultMaxRetryWindow = 4 * time.Minute
	backoffBaseDuration   = 30 * time.Second
	timeFormat            = time.RFC3339
)

var (
	retryRand = mathutils.NewSynchronizedRandProviderFromClock()

	// NOTE:  We employ a stateless backoff implementation here (versus, for example, the stateful github.com/cenkalti/backoff)
	// because, chances are, each subsequent retry attempt will occur on a separate service-host/queue worker.
	// As currently configured, we get the same backoff range (60-120 seconds) we had back before we acknowledged
	// aqueduct jobs we wanted to retry. 100% jitter results in backoffs as short as 0ms,
	// regardless of duration or attempt number, and is not a good fit for retrying aqueduct jobs.
	// Our retryable errors are often related to replication lag or delayed background jobs and
	// there's a lot of overhead in requeuing and reprocessing a job, relative to resending an http request.
	// If you increase the jitter, consider increasing the max number of attempts or switching to a time-based limit.
	backoffStrategy = prescribedBackoff(retryRand, .33)
)

type jobAttempt struct {
	// the aqueduct job id that originally delivered this payload. The job id changes each time we requeue the job.
	originalAqueductJobID string
	originalReceiveAt     time.Time
	// All retry attempts are expected to be queued *and* delivered before the retryUntil time elapses.
	retryUntil time.Time
	// A one-based attempt number.  (Inital attempt is attemptNumber=1.  First retry is attemptNumber=2.)
	attemptNumber uint
}

func (ja *jobAttempt) isRetry() bool {
	return ja.attemptNumber > 1
}

func ComputeBackoff(oneBasedAttemptNumber uint) time.Duration {
	// ahttp.BackoffStrategy expects a zero-based attempt number.
	return backoffStrategy(oneBasedAttemptNumber-1, backoffBaseDuration)
}

func extractAttemptDetails(r *aqueduct.ReceiveResult, recvAt time.Time) (*jobAttempt, error) {
	ja := &jobAttempt{}

	if jobID, ok := r.Headers[headerOriginalAqueductJobID]; ok {
		ja.originalAqueductJobID = jobID
	} else {
		// If the header isn't set, we received the original aqueduct job
		ja.originalAqueductJobID = r.ID
	}

	origRecvAt, ok, err := getTimeHeader(&r.Job, headerOriginalReceiveTime)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to convert receive time header value to Time")
	}
	if ok {
		ja.originalReceiveAt = origRecvAt
	} else {
		ja.originalReceiveAt = recvAt
	}

	finalTime, ok, err := getTimeHeader(&r.Job, headerFinalAttemptTime)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to convert final attempt time header value to Time")
	}
	if ok {
		ja.retryUntil = finalTime
	} else {
		ja.retryUntil = ja.originalReceiveAt.Add(defaultMaxRetryWindow)
	}

	if attempt, ok := r.Headers[headerJobAttempt]; ok {
		attemptNumber, err := strconv.Atoi(attempt)
		if err != nil {
			return nil, errors.Wrap(err, "Unable to convert attempt header value to integer")
		}
		if attemptNumber < 1 {
			return nil, errors.WithStack(errors.New("attempt header value is expected to be one-based"))
		}
		ja.attemptNumber = uint(attemptNumber)
	} else {
		ja.attemptNumber = 1
	}

	return ja, nil
}

func (ja *jobAttempt) possiblyExtendRetryWindow(retryDuration time.Duration) bool {
	newFinalTime := ja.originalReceiveAt.Add(retryDuration)
	if newFinalTime.After(ja.retryUntil) {
		ja.retryUntil = newFinalTime
		return true
	}

	return false
}

func (ja *jobAttempt) addAttemptDetails(j *aqueduct.Job) {
	if j.Headers == nil {
		j.Headers = make(map[string]string)
	}

	j.Headers[headerOriginalAqueductJobID] = ja.originalAqueductJobID
	setTimeHeader(j, headerOriginalReceiveTime, ja.originalReceiveAt)
	setTimeHeader(j, headerFinalAttemptTime, ja.retryUntil)
	j.Headers[headerJobAttempt] = fmt.Sprint(ja.attemptNumber)
}

func setTimeHeader(j *aqueduct.Job, headerName string, t time.Time) {
	if j.Headers == nil {
		j.Headers = make(map[string]string)
	}

	j.Headers[headerName] = t.Format(timeFormat)
}

func getTimeHeader(j *aqueduct.Job, headerName string) (time.Time, bool, error) {
	tstr, ok := j.Headers[headerName]
	if !ok {
		return time.Time{}, ok, nil
	}

	t, err := time.Parse(timeFormat, tstr)
	if err != nil {
		return time.Time{}, ok, errors.Wrap(err, "Unable to convert deliver at value to Time")
	}
	return t, ok, nil
}

// prescribedBackoff is a backoff strategy tailored to fit the specific needs of queueworkers.
// In general, all retries are expected to be complete within 4 minutes.
// Under some circumstances, the retry window gets extended to 10 minutes.
func prescribedBackoff(r *mathutils.SynchronizedRandProvider, maxJitterScale float64) ahttp.BackoffStrategy {
	// Example with a 30-second base duration (see const definition backoffBaseDuration2024 above),
	// the following scale factors result in backoff durations of:
	//
	// 0-based Attempt:   0 |    1 |    2 |    3 |    4 | ... |    n  |
	//    attempt-wise:   0s|   90s|  120s|  150s|  210s| ... |  210s | <-- final scale factor is reused for any "out-of-bounds" attempts
	// or cumulatively:   0s|   90s|  210s|  360s|  570s| ... | >600s |
	//  equiv. minutes:   0m|  1.5m|  3.5m|  6.0m| 9.50m| ... | > 10m | <-- 10 minutes is beyond the max retry window
	scale := []float64{0.000, 3.000, 4.000, 5.000, 7.000}

	// attemptNumber is zero-based.  The initial attempt is attemptNumber=0.
	// Retries start at attemptNumber=1.
	return func(zeroBasedAttemptNumber uint, baseDuration time.Duration) time.Duration {
		// This strategy adheres to the following formula:
		//    effectiveBackoff = naturalBackoff + (j * naturalBackoff)
		//    (See ahttp.RandomizedExponentialBackoff for detailed comments
		//     on formulas governing this style of backoff.)
		safeIndex := min(int(zeroBasedAttemptNumber), len(scale)-1)
		naturalBackoff := timeutils.ScaleDuration(scale[safeIndex], baseDuration)

		// compute the jitter scale factor, j.
		// (see ahttp.RandomizedExponentialBackoff for detailed explanation)
		j := mathutils.RandomFloat64(r, -maxJitterScale, maxJitterScale)
		effectiveBackoff := naturalBackoff + timeutils.ScaleDuration(j, naturalBackoff)
		return effectiveBackoff
	}
}
