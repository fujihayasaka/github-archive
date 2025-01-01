package queueworker

import (
	"context"
	"fmt"
	"runtime/debug"
	"strconv"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/github/go-queryannotations"
	"github.com/github/go-queryannotations/annotation"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/clock"
)

const (
	// headerDeliverAt is used to log the deliverAt time upon receive.
	headerDeliverAt = "x-launch-deliver-at"
)

// JobProcessor is able to process jobs from aqueduct, returning an error if there is one.
type JobProcessor interface {
	Process(context.Context, *observability.Observability, []byte, bool) error
}

type worker struct {
	cfg   QueueWorkerConfig
	ID    string
	obs   *observability.Observability
	aq    aq.Client
	jp    JobProcessor
	clock clock.Clock
	tags  map[string]string
}

type workResult string

var resultSuccess workResult = "success" // Does not mean no errors processing the job, just that a job was found and processed to some conclusion
var resultNoneFound workResult = "none-found"
var resultAqueductError workResult = "aqueduct-error"
var resultInitializeError workResult = "initialize-error"

func (w *worker) Work(ctx context.Context) (result workResult, nextRecvAt time.Time) {
	ctx = appcontext.EnsureRequestID(ctx)
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	ctx, span := tracing.Start(ctx, trace.WithSpanKind(trace.SpanKindConsumer))
	defer span.End()

	resp, aqBackoff, recvErr := w.fetchJob(ctx)
	nextRecvAt = w.clock.Now().Add(aqBackoff)

	if recvErr != nil {
		w.obs.Error(ctx, "error talking to Aqueduct", kvp.Err(recvErr))
		return resultAqueductError, nextRecvAt
	}
	if resp == nil {
		// Nothing found, so cooperatively backoff and receive again in another loop
		return resultNoneFound, nextRecvAt
	}

	recvAt := w.clock.Now()

	ctx = ctxstash.WithAqueductJobID(ctxstash.WithFields(ctx,
		kvp.String("gh.aqueduct.app", resp.App),
		kvp.String("gh.aqueduct.queue.name", resp.Queue),
		kvp.Int("gh.aqueduct.delivery_attempt", resp.DeliveryAttempt),
		kvp.Int("gh.aqueduct.max_delivery_attempts", resp.MaxDeliveryAttempts),
	), resp.Job.ID)

	// Ensure jobID and queue are added to any queries run during job processing.
	ctx = queryannotations.WithQueryAnnotations(ctx, annotation.JobID(resp.Job.ID), annotation.Job(resp.Job.Queue))

	attempt, err := extractAttemptDetails(resp, recvAt)
	if err != nil {
		w.obs.Report(ctx, errors.Wrap(err, "error extracting job attempt details"))
		return resultInitializeError, nextRecvAt
	}

	// Precompute a backoff duration for a theoretical NEXT ATTEMPT
	// to see if we can squeeze one more attempt in before our retry window elapses.
	backoffDuration := ComputeBackoff(attempt.attemptNumber + 1)
	isFinalAttempt := recvAt.Add(backoffDuration).After(attempt.retryUntil)

	// The original aqueduct job id can be used to find logs for all job attempts.
	maxRetryWindow := attempt.retryUntil.Sub(attempt.originalReceiveAt)
	ctx = ctxstash.WithOrigAqueductJobID(ctxstash.WithFields(ctx,
		kvp.Uint("gh.aqueduct.job.attempt", attempt.attemptNumber),
		kvp.Duration("gh.aqueduct.job.max_retry_window_sec", maxRetryWindow),
		kvp.Bool("gh.aqueduct.job.final_attempt", isFinalAttempt),
	), attempt.originalAqueductJobID)

	// resp.Job.DeliverAt isn't set on receive. Instead we retrieve it from a header we supplied.
	deliverAt, _, err := getTimeHeader(&resp.Job, headerDeliverAt)
	if err != nil {
		w.obs.Report(ctx, errors.Wrap(err, "error parsing deliver_at header"))
		return resultInitializeError, nextRecvAt
	}

	fields := []kvp.Field{
		kvp.Time("gh.aqueduct.job.sent_at", resp.SentAt),
		kvp.Time("gh.aqueduct.job.received_at", recvAt),
	}
	if !deliverAt.IsZero() {
		fields = append(fields, kvp.Time("gh.aqueduct.job.deliver_at", deliverAt))
	}
	w.obs.Log(ctx, "aqueduct job received", fields...)

	jobIsRetryable, err := w.processJob(ctx, resp, deliverAt, recvAt, attempt, isFinalAttempt)
	if err != nil {
		w.obs.Report(ctx, errors.Wrap(err, "error processing job from queue"))

		if isFinalAttempt {
			w.obs.Error(ctx, "aqueduct job processing failed and retries have been exhausted.", kvp.Err(err))
		} else {
			w.obs.Error(ctx, "aqueduct job processing failed", kvp.Err(err))
		}
	}

	if jobIsRetryable {
		if !isFinalAttempt {
			if err := w.requeueJob(ctx, resp, attempt, backoffDuration); err != nil {
				w.obs.Report(ctx, errors.Wrap(err, "error requeuing job"))

				// If we couldn't requeue the job, return _without_ acking. That way aqueduct will deliver the job again, up to MaxDeliveryAttempts.
				return resultAqueductError, nextRecvAt
			}
		} else {
			// If we see a high number of incomplete jobs, we may need to increase the number of redeliveries or mark
			// some errors as non-retryable.
			w.obs.Log(ctx, "Job can't be retried. No retries remaining.")
			w.obs.Counter(ctx, "queue.worker.exhausted_retries", nil, 1)
		}
	}

	if err := w.ackJob(ctx, resp); err != nil {
		w.obs.Report(ctx, errors.Wrap(err, "error acking job from queue"))

		return resultAqueductError, nextRecvAt
	}

	return resultSuccess, nextRecvAt
}

func (w *worker) Wait(ctx context.Context, aqBackoff time.Duration) {
	w.obs.Debug(ctx, "waiting prior to checking Aqueduct queues again",
		kvp.Duration("gh.aqueduct.remaining_backoff_sec", aqBackoff),
		kvp.String("gh.aqueduct.worker.id", w.ID),
		kvp.String("gh.aqueduct.client_id", w.aq.ID()),
	)

	tick := w.clock.NewTicker(aqBackoff)
	defer tick.Stop()

	select {
	case <-ctx.Done():
	case <-tick.C():
	}
}

func (w *worker) fetchJob(ctx context.Context) (resp *aqueduct.ReceiveResult, aqBackoff time.Duration, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.aqueduct.worker.id", w.ID),
		kvp.String("gh.aqueduct.client_id", w.aq.ID()),
	)

	b := backoff.NewExponentialBackOff()
	b.MaxElapsedTime = 60 * time.Second
	b.MaxInterval = 30 * time.Second

	attempt := 0
	receiveOp := func() error {
		rOpts := aq.ReceiveOptions{
			Timeout:    time.Duration(w.cfg.AqueductTimeoutMs) * time.Millisecond,
			WorkerID:   w.ID,
			WorkerPool: w.cfg.AqueductWorkerPool,
			WorkerTags: w.tags,
		}
		resp, aqBackoff, err = w.aq.Receive(ctx, w.cfg.AqueductApp, w.cfg.AqueductQueues, rOpts)
		if err != nil {
			w.obs.Error(ctx, "aqueduct error receiving job", kvp.Err(err))
			w.obs.Counter(ctx, "queue.worker.fetch_job", statter.Tags{"status": "error", "retry_num": strconv.Itoa(attempt)}, 1)
			return err
		}
		return nil
	}
	err = backoff.RetryNotify(receiveOp, b, func(err error, d time.Duration) { attempt++ })
	if err != nil {
		return nil, aqBackoff, errors.Wrap(err, "failed poll for fresh job from aqueduct")
	}

	// if no payload, this isn't a job it's a timeout waiting; loop again
	if resp == nil || len(resp.Payload) == 0 {
		w.obs.Counter(ctx, "queue.worker.fetch_job", statter.Tags{"status": "none-found"}, 1)
		return nil, aqBackoff, nil
	}

	mw.TagStatsWith(ctx, reqmeta.Tags{
		"queue": resp.Queue,
	})

	w.obs.Counter(ctx, "queue.worker.fetch_job", statter.Tags{"status": "success"}, 1)

	return resp, aqBackoff, nil
}

func (w *worker) processJob(ctx context.Context, recvResult *aqueduct.ReceiveResult, deliverAt, recvAt time.Time, attempt *jobAttempt, isFinalAttempt bool) (isRetryable bool, retErr error) {
	jobAttemptStr := fmt.Sprint(attempt.attemptNumber)
	defer func() {
		if r := recover(); r != nil {
			err, ok := r.(error)
			if !ok {
				err = fmt.Errorf("%v", r)
			}
			w.obs.Report(ctx, errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
			w.obs.Counter(ctx, "queue.worker.process_job", statter.Tags{"status": "panic", "job_attempt": jobAttemptStr}, 1)
			isRetryable = true
			retErr = err
		}
	}()

	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Take note if this job is an Aqueduct retry
	mw.TagStatsWith(ctx, reqmeta.Tags{
		"is_job_retry": strconv.FormatBool(attempt.isRetry()),
	})

	hbDone := make(chan struct{})
	hbCtx, cancelHeartbeats := context.WithCancel(ctx)
	go w.sendHeartbeatPeriodically(hbCtx, recvResult, hbDone)
	defer func() {
		cancelHeartbeats()
		// wait for sendHeartbeatPeriodically to exit. We do this to avoid flaky tests and any race conditions aqueduct might have
		// around acks and heartbeats being sent at the same time.
		<-hbDone
	}()

	jobObs := observability.New(w.obs.Logger, w.obs.Statter)
	jobObs.AddCheckpoint(observability.AqJobRecvAtCheckpoint, recvAt)
	// Adding this only on retry complicates GetCheckpointTime calls
	jobObs.AddCheckpoint(observability.AqOrigJobRecvAtCheckpoint, attempt.originalReceiveAt)

	// Record when the job was sent if delivery wasn't intentionally delayed.
	if deliverAt.IsZero() {
		jobObs.AddCheckpoint(observability.AqJobSentAtCheckpoint, recvResult.SentAt)
		jobObs.Timing(ctx, "delays.job_sent_at.job_recv_at", statter.Tags{}, recvAt.Sub(recvResult.SentAt))
	}

	if jpErr := w.jp.Process(ctx, jobObs, recvResult.Payload, isFinalAttempt); jpErr != nil {
		// Don't consider user errors as job processing failures.
		if !terrors.IsUserError(jpErr) {
			isRetryable = terrors.IsRetryable(jpErr)

			w.obs.Error(ctx, "JobProcessor failed",
				kvp.Err(jpErr),
				kvp.Bool("gh.launch.job.processing_is_retryable", isRetryable))

			errorReason := "other"
			if terrors.IsRateLimitError(jpErr) {
				errorReason = "rate_limit_error"
			}
			if terrors.IsRefResolutionError(jpErr) {
				errorReason = "failed_ref_resolution"
			}
			w.obs.Counter(ctx, "queue.worker.process_job", statter.Tags{
				"status":              "failure",
				"error_is_retryable":  strconv.FormatBool(isRetryable),
				"job_attempt":         jobAttemptStr,
				"job_will_be_retried": strconv.FormatBool(isRetryable && !isFinalAttempt),
				"error_reason":        errorReason,
			}, 1)

			// Try extending the job's final attempt time if there are any retryable errors that specify durations in the error chain.
			terrors.FindRetryableDurationErrors(jpErr, func(dErr terrors.RetryableDurationError) {
				if !isFinalAttempt && attempt.possiblyExtendRetryWindow(dErr.RetryDuration()) {
					w.obs.Log(ctx, "Job attempt duration extended",
						kvp.Duration("gh.aqueduct.job.processing_retry_duration_sec", dErr.RetryDuration()),
						kvp.Err(dErr))
				}
			})

			// Don't propagate the job processor error. There can be well-known errors that should trigger a retry but shouldn't be reported.
			return isRetryable, nil
		}

		w.obs.Debug(ctx, "JobProcessor resulted in user error",
			kvp.Err(jpErr))
	}

	w.obs.Counter(ctx, "queue.worker.process_job", statter.Tags{
		"status":      "success",
		"job_attempt": jobAttemptStr,
	}, 1)

	return false, nil
}

func (w *worker) requeueJob(ctx context.Context, r *aqueduct.ReceiveResult, attempt *jobAttempt, backoffDuration time.Duration) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	attempt.attemptNumber++
	deliverAt := time.Now().Add(backoffDuration)
	newJob := aqueduct.Job{
		App:       r.App,
		Queue:     r.Queue,
		Payload:   r.Payload,
		DeliverAt: deliverAt,
	}

	// Add the job attempt details to the job headers
	attempt.addAttemptDetails(&newJob)

	// Add the deliverAt time to the job headers
	setTimeHeader(&newJob, headerDeliverAt, deliverAt)

	sOpts := make([]aqueduct.SendOption, 0, 1)
	if launchconfig.UseAqueductJobTTL() {
		// REVIEW: Should we adjust this TTL to expire coincident with our max wait time???
		sOpts = append(sOpts, aqueduct.WithTTL(aqueduct.JobTTL))
	}

	status := "success"
	defer func() {
		statterTags := statter.Tags{
			"status":      status,
			"queue":       r.Queue,
			"job_attempt": fmt.Sprint(attempt.attemptNumber),
		}
		w.obs.Counter(ctx, "queue.worker.requeue_job", statterTags, 1)
		w.obs.Timing(ctx, "queue.worker.requeue_job.backoff_duration", statterTags, backoffDuration)
	}()

	newJobID, err := w.aq.Send(ctx, newJob, sOpts...)
	if err != nil {
		status = "failed"
		return errors.Wrapf(err, "failed to requeue Aqueduct job: %s", r.Job.ID)
	}

	formattedBackoffDuration := fmt.Sprintf("%.3f", backoffDuration.Seconds())
	w.obs.Log(ctx, "aqueduct job requeued",
		kvp.String("gh.aqueduct.new_job.id", newJobID),
		kvp.Uint("gh.aqueduct.job.attempt", attempt.attemptNumber),
		kvp.String("gh.launch.duration_sec", formattedBackoffDuration))

	return nil
}

func (w *worker) ackJob(ctx context.Context, r *aqueduct.ReceiveResult) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := w.aq.Ack(ctx, r.Job, aqueduct.AckSuccess)
	if err != nil {
		w.obs.Counter(ctx, "queue.worker.ack_job", statter.Tags{"status": "failed"}, 1)
		return errors.Wrapf(err, "failed to ack Aqueduct job: %s", r.Job.ID)
	}

	w.obs.Log(ctx, "aqueduct job acked")
	w.obs.Counter(ctx, "queue.worker.ack_job", statter.Tags{"status": "success"}, 1)
	return nil
}

func (w *worker) sendHeartbeatPeriodically(ctx context.Context, r *aqueduct.ReceiveResult, done chan struct{}) {
	defer close(done)

	startTime := w.clock.Now()
	lastSuccessOrStartTime := w.clock.Now()
	// the start time, last success time or the last time we reported an error.
	lastCheckpointTime := w.clock.Now()
	failures := 0
	totalFailures := 0
	totalSuccesses := 0

	ticker := w.clock.NewTicker(w.cfg.HeartbeatAttemptInterval)
	defer ticker.Stop()

HeartbeatLoop:
	for {
		select {
		case <-ticker.C():
			if err := w.sendHeartbeat(ctx, r); err != nil {
				totalFailures++

				// The occasional failed attempt is fine, but if we exceed maxTimeWithoutHeartbeat report an error.
				// TODO: Cancel the jobProcessor's context in addition to erroring?
				failures++
				timeSinceCheckpoint := w.clock.Since(lastCheckpointTime)

				if timeSinceCheckpoint > w.cfg.MaxTimeWithoutHeartbeat {
					timeSinceSuccess := w.clock.Since(lastSuccessOrStartTime)

					w.obs.Report(ctx, errors.Wrap(err, "Too much time without successful heartbeat"),
						kvp.Int("gh.launch.heartbeat_failed_heartbeats", failures),
						kvp.Duration("gh.launch.heartbeat_elapsed_time_sec", timeSinceSuccess),
						kvp.Err(err))

					// Wait another max time interval before reporting another error.
					lastCheckpointTime = w.clock.Now()
				}
			} else {
				totalSuccesses++

				// reset failure tracking
				failures = 0
				lastCheckpointTime = w.clock.Now()
				lastSuccessOrStartTime = w.clock.Now()
			}
		case <-ctx.Done():
			break HeartbeatLoop
		}
	}

	w.obs.Debug(ctx, "Done sending heartbeats",
		kvp.Int("gh.launch.heartbeat_failed_heartbeats", totalFailures),
		kvp.Int("gh.launch.heartbeat_successful_heartbeats", totalSuccesses),
		kvp.Duration("gh.launch.heartbeat_elapsed_time_sec", w.clock.Since(startTime)))
}

func (w *worker) sendHeartbeat(ctx context.Context, r *aqueduct.ReceiveResult) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := w.aq.Heartbeat(ctx, r.Job)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			w.obs.Counter(ctx, "queue.worker.heartbeat", statter.Tags{"status": "canceled"}, 1)
			return nil
		}
		w.obs.Counter(ctx, "queue.worker.heartbeat", statter.Tags{"status": "failed"}, 1)
		w.obs.Error(ctx, "Heartbeat attempt failed", kvp.Err(err))

		return errors.Wrapf(err, "failed to send heartbeat for job")
	}

	w.obs.Counter(ctx, "queue.worker.heartbeat", statter.Tags{"status": "success"}, 1)
	return nil
}
