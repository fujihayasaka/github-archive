package aqueduct

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"reflect"
	"runtime/debug"
	"strconv"
	"sync"
	"time"

	"github.com/avast/retry-go"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

const (
	defaultReceiveTimeout  = 5 * time.Second
	defaultAckStatus       = AckSuccess
	nanoIDAlphabet         = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
	defaultIDEntropyLength = 10
)

type workerConfig struct {
	receiveTimeout       *time.Duration
	heartbeatCfg         *HeartbeatConfig
	retrierCfg           *RetrierConfig
	errPolicy            JobErrorPolicy
	invalidPayloadPolicy InvalidPayloadPolicy
	logger               log.Logger
	statsConfig          *StatsConfig
	shuffleQueues        bool
	tags                 map[string]string
	pool                 string
}

func newWorkerConfig(opts []WorkerOption) (*workerConfig, error) {
	cfg := workerConfig{
		errPolicy:            NackJobErr,
		invalidPayloadPolicy: InvalidPayloadPolicyReject,
	}
	for _, o := range opts {
		if err := o(&cfg); err != nil {
			return nil, fmt.Errorf("applying worker option: %w", err)
		}
	}
	return &cfg, nil
}

// WorkerOption is the functional option type for configuring a Worker.
type WorkerOption func(*workerConfig) error

// WithReceiveTimeout is the WorkerOption for overriding the default receive
// timeout. It returns an error when negative.
func WithReceiveTimeout(d time.Duration) WorkerOption {
	return func(wc *workerConfig) error {
		if d < 0 {
			return errors.New("receive timeout must be non-negative")
		}
		wc.receiveTimeout = &d
		return nil
	}
}

// WithTags is the WorkerOption for setting worker tags. Tags are optional key-values that can be
// used to pause subsets of workers. For example, a "site" tag could be used to pause workers in a
// single site.
func WithTags(tags map[string]string) WorkerOption {
	return func(wc *workerConfig) error {
		wc.tags = tags
		return nil
	}
}

// WithPool is the WorkerOption that sets the aqueduct worker pool. A worker pool represents
// a logical group of workers that work the same queues. The pool is used to calculate pool metrics
// in Aqueduct and enable features like execution time throttling.
func WithPool(pool string) WorkerOption {
	return func(wc *workerConfig) error {
		wc.pool = pool
		return nil
	}
}

// WithHeartbeatConfig is the WorkerOption for setting a HeartbeatConfig. It
// returns an error when nil.
func WithHeartbeatConfig(hc *HeartbeatConfig) WorkerOption {
	return func(wc *workerConfig) error {
		if hc == nil {
			return errors.New("heartbeat config must be non-nil")
		}
		wc.heartbeatCfg = hc
		return nil
	}
}

// WithRetrierConfig is the WorkerOption for setting a RetrierConfig to control
// the retry behavior of Worker failed Worker requests. It returns an error
// when nil.
func WithRetrierConfig(r *RetrierConfig) WorkerOption {
	return func(wc *workerConfig) error {
		if r == nil {
			return errors.New("retrier config must be non-nil")
		}
		wc.retrierCfg = r
		return nil
	}
}

// WithJobErrorPolicy is the WorkerOption to set the error policy to control
// what action is taken when a JobHandler returns an error.
func WithJobErrorPolicy(p JobErrorPolicy) WorkerOption {
	return func(wc *workerConfig) error {
		wc.errPolicy = p
		return nil
	}
}

// WithInvalidPayloadPolicy is the WorkerOption to set the error policy to
// control what action is taken when a worker encounters a job with an invalid
// payload. The default policy is InvalidPayloadPolicyDiscard.
func WithInvalidPayloadPolicy(p InvalidPayloadPolicy) WorkerOption {
	return func(wc *workerConfig) error {
		wc.invalidPayloadPolicy = p
		return nil
	}
}

// WithLogger is the WorkerOption to set the logger to be used by a worker. It
// returns an error when nil.
func WithLogger(l log.Logger) WorkerOption {
	return func(wc *workerConfig) error {
		if l == nil {
			return errors.New("logger must be non-nil")
		}
		wc.logger = l
		return nil
	}
}

// WithWorkerStats is the WorkerOption to set a StatsConfig to control how
// worker stats are reported. It returns an error when nil.
func WithWorkerStats(sc *StatsConfig) WorkerOption {
	return func(wc *workerConfig) error {
		if sc == nil {
			return errors.New("stats config must be non-nil")
		}
		wc.statsConfig = sc
		return nil
	}
}

// WithShuffleQueues will call the Aqueduct Receive API with the order of `queues`
// in randomized order.
func WithShuffleQueues() WorkerOption {
	return func(config *workerConfig) error {
		config.shuffleQueues = true
		return nil
	}
}

// Worker is a type that provides a fully instrumented higher level job
// processing abstraction on top of a Client through the use of the JobHandler
// API. It manages job lifecycle including heartbeating and acking.
//
// This is thread-safe, but we generally recommend using multiple instances of Workers
// to achieve concurrency instead of concurrent invocations of ProcessJob on the same Worker.
// This is because of how Aqueduct high availability uses the workerID to choose the underlying
// aqueduct cluster.
//
// It must be created using NewWorker.
type Worker struct {
	ID     string
	client Client
	app    string
	queues []string
	tags   map[string]string
	pool   string

	// Preserve thread-safety
	mu sync.Mutex
	// Mutable; the time between subsequent receives when a worker is considered idle or not processing a job
	// Note: This value will not be accurate if a worker is shared among goroutines.
	idleStartTime time.Time
	// Mutable; track the last backoff value to avoid over reporting worker idle time for previous time
	// windows. At this time, workers do not emit idle heartbeats that Aqueduct could use
	// to compute the correct worker idle time.
	// Note: This value will not be accurate if a worker is shared among goroutines.
	lastBackoff time.Duration

	receiveTimeout time.Duration

	handler              JobHandler
	errPolicy            JobErrorPolicy
	invalidPayloadPolicy InvalidPayloadPolicy

	heartbeatCfg *HeartbeatConfig
	retrierCfg   *RetrierConfig

	shuffleQueues bool

	log   log.Logger
	stats stats.Client

	backoff chan (time.Duration)

	// closed indicates that a call to close the worker happened.
	closed chan struct{}
	// done indicates that the timeout to close the worker has elapsed.
	done chan struct{}
}

// NewWorker returns a new Worker for processing jobs from the specified app
// and queue(s) with the provided JobHandler. It applies any provided
// WorkerOptions returning an error if encountered.
//
// Unless overridden by a WorkerOption it uses the default HeartbeatConfig,
// RetrierConfig, and StatsConfig.
func NewWorker(client Client, app string, queues []string, jh JobHandler, opts ...WorkerOption) (*Worker, error) {
	if client == nil || reflect.ValueOf(client).IsNil() {
		return nil, errors.New("client must be non-nil")
	}
	if app == "" {
		return nil, errors.New("app must be non-empty")
	}
	if len(queues) == 0 {
		return nil, errors.New("queues must be non-empty")
	}
	for i, q := range queues {
		if q == "" {
			return nil, fmt.Errorf("queue[%d] must be non-empty", i)
		}
	}
	if jh == nil {
		return nil, errors.New("job handler must be non-nil")
	}

	cfg, err := newWorkerConfig(opts)
	if err != nil {
		return nil, fmt.Errorf("configuring worker: %w", err)
	}

	rcvTimeout := defaultReceiveTimeout
	if cfg.receiveTimeout != nil {
		rcvTimeout = *cfg.receiveTimeout
	}

	hb := cfg.heartbeatCfg
	if hb == nil {
		hb, _ = NewHeartbeatConfig()
	}

	r := cfg.retrierCfg
	if r == nil {
		r, _ = NewRetrierConfig()
	}

	workerTags := cfg.tags

	workerMetadata := NewWorkerMetadata(cfg.pool)

	logger, err := newWorkerLogger(cfg.logger)
	if err != nil {
		return nil, err
	}

	logger = logger.WithFields(kvpsForWorkerMetadata(workerMetadata, client.ID())...)

	sc := cfg.statsConfig
	if sc == nil {
		sc, _ = NewStatsConfig()
	}
	statsClient, err := sc.client("aqueduct.worker", stats.Tags{})
	if err != nil {
		return nil, fmt.Errorf("creating stats reporter: %w", err)
	}

	worker := Worker{
		ID:                   workerMetadata.ID,
		client:               client,
		app:                  app,
		queues:               queues,
		receiveTimeout:       rcvTimeout,
		handler:              jh,
		errPolicy:            cfg.errPolicy,
		invalidPayloadPolicy: cfg.invalidPayloadPolicy,
		shuffleQueues:        cfg.shuffleQueues,
		heartbeatCfg:         hb,
		retrierCfg:           r,
		log:                  logger,
		stats:                statsClient,
		tags:                 workerTags,
		backoff:              make(chan (time.Duration), 1000),
		pool:                 workerMetadata.Pool,
		idleStartTime:        time.Now(),
		closed:               make(chan struct{}),
		done:                 make(chan struct{}),
	}

	return &worker, nil
}

// ProcessJob executes the processing of a single job blocking until complete.
// If a terminal error is encountered it returns early with a WorkerError
// containing the details. It is safe for concurrent use.
//
// The processing flow is split into 4 stages: receive, heartbeat, handle, ack.
//
// First a blocking receive is attempted with the configured delivery timeout.
// If no job is received, it returns early with a nil error.
//
// Second a goroutine is spawned to that uses the configured HeartbeatConfig to
// periodically send job heartbeats until the method returns. Any heartbeat
// requests that fail will be retried using the RetrierConfig. If a terminal
// heartbeat error is encountered it will be logged.
//
// Third the configured JobHandler is invoked with the received job. If the
// handler returns an error and the IgnoreJobErr policy is used it will return
// early. JobHandler panics will be recovered and treated as an error.
//
// Fourth the job will be ack'd. If the handler returned an error the
// configured JobErrorPolicy will control which AckStatus is provided. If the
// ack request fails it will be retried using the configured RetrierConfig. If
// all retry attempts fail it will return an error.
//
// The provided context is passed all Client requests and the JobHandler.
// Context cancelation will terminate in-flight Client requests and return
// early with the context error. The caller is responsible for handling context
// errors in their JobHandler based on their requirements.
func (w *Worker) ProcessJob(ctx context.Context) error {
	kvps := kvpsForAppQueues(w.app, w.queues)

	select {
	case backoff := <-w.backoff:
		w.stats.DistributionMs("job.receive.backoff", stats.Tags{}, backoff)
		w.log.Debug(fmt.Sprintf("worker %s backing off for %d seconds", w.ID, int(backoff.Seconds())))
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-w.closed:
			return nil
		case <-time.After(backoff):
		}
	default:
	}

	type resp struct {
		result      *ReceiveResult
		nextBackoff time.Duration
		err         error
	}
	c := make(chan resp)
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		result, nextBackoff, err := w.receive(ctx)
		c <- resp{
			result:      result,
			nextBackoff: nextBackoff,
			err:         err,
		}
	}()
	var result *ReceiveResult
	var nextBackoff time.Duration
	var err error
	select {
	case r := <-c:
		result = r.result
		nextBackoff = r.nextBackoff
		err = r.err
	case <-w.closed:
		cancel()
		<-c
		return nil
	}
	defer cancel()

	if err != nil {
		if err == context.Canceled || err == context.DeadlineExceeded {
			w.log.WithError(err).Debug("error receiving job")
		} else {
			w.log.WithError(err).Error("error receiving job")
		}
		return &WorkerError{
			Source: ReceiveErrSource,
			Err:    err,
		}
	}

	if nextBackoff > 0 {
		w.backoff <- nextBackoff
	}
	w.setLastBackoff(nextBackoff)

	if result == nil {
		w.log.Debug("no job available", kvps...)
		// Don't double count idle pop time from empty receives; Aqueduct already accounts for it
		w.setIdleStartTime()
		return nil
	}

	return w.process(ctx, result, err)
}

func (w *Worker) process(ctx context.Context, result *ReceiveResult, err error) error {
	c := make(chan error)
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		job := result.Job

		kvps := kvpsForJob(job)
		w.log.Debug("received job", kvps...)

		if !result.ValidPayload {
			w.log.WithError(err).Error("invalid job payload HMAC")

			if w.invalidPayloadPolicy == InvalidPayloadPolicyReject {
				if err := w.ack(ctx, job, AckFailure); err != nil {
					c <- &WorkerError{
						Source: AckErrSource,
						Err:    err,
					}
					return
				}

				c <- nil
				return
			}
		}

		hbCtx, hbCancel := context.WithCancel(ctx)
		defer hbCancel()
		go func() {
			err := w.heartbeat(hbCtx, job)
			if err != nil && !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
				w.log.WithError(err).Error("error heartbeating job")
			}
		}()

		ackStatus := defaultAckStatus
		if err := w.handle(ctx, *result); err != nil {
			w.log.WithError(err).Error("error executing job handler")

			switch w.errPolicy {
			case IgnoreJobErr:
				c <- nil
				return
			case AckJobErr:
				ackStatus = AckSuccess
			case NackJobErr:
				ackStatus = AckFailure
			}
		}

		if err := w.ack(ctx, job, ackStatus); err != nil {
			c <- &WorkerError{
				Source: AckErrSource,
				Err:    err,
			}
			return
		}

		c <- nil
	}()

	select {
	case <-ctx.Done():
		cancel()
		return ctx.Err()
	case <-w.done:
		cancel()
		return <-c
	case err := <-c:
		cancel()
		return err
	}
}

// Close the worker, gracefully if possible waiting until timeout.
func (w *Worker) Close(timeout time.Duration) {
	// The behaviour is controlled by two channels:
	// - closed. This is immediately closed when this method is called.
	// - done. This is closed when closing timeouts.
	// Note that closing on done happens in its own goroutine and this method
	// will not wait till that happens. The caller is expected to wait until
	// the job processing finishes instead, which may be quicker than waiting
	// for the timeout.
	close(w.closed)
	time.AfterFunc(timeout, func() { close(w.done) })
}

func (w *Worker) getIdleTimeMs() uint64 {
	w.mu.Lock()
	defer w.mu.Unlock()
	// Avoid inflating worker idle time when becoming active from a backoff.
	return uint64(time.Since(w.idleStartTime).Milliseconds() - w.lastBackoff.Milliseconds())
}

func (w *Worker) setIdleStartTime() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.idleStartTime = time.Now()
}

func (w *Worker) setLastBackoff(backoff time.Duration) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.lastBackoff = backoff
}

func (w *Worker) receive(ctx context.Context) (*ReceiveResult, time.Duration, error) {
	start := time.Now()

	queues := w.queues
	if w.shuffleQueues {
		queues = make([]string, len(queues))
		copy(queues, w.queues)
		rand.Shuffle(len(queues), func(i, j int) {
			queues[i], queues[j] = queues[j], queues[i]
		})
	}

	kvps := kvpsForAppQueues(w.app, queues)
	w.log.Debug("attempting to receive job", kvps...)

	var rr *ReceiveResult
	var backoff time.Duration
	err := w.doWithRetry(ctx, func() error {
		var err error

		rr, backoff, err = w.client.Receive(ctx, w.app, queues, ReceiveOptions{
			Timeout:      w.receiveTimeout,
			WorkerID:     w.ID,
			WorkerTags:   w.tags,
			WorkerPool:   w.pool,
			WorkerIdleMs: w.getIdleTimeMs(),
		})
		if err != nil {
			w.log.WithError(err).Debug("receive attempt error, may retry")
		}
		return err
	})

	w.stats.Timing("job.receive.time", stats.Tags{
		"success":      strconv.FormatBool(err == nil),
		"job_received": strconv.FormatBool(rr != nil),
	}, time.Since(start))

	return rr, backoff, err
}

func (w *Worker) heartbeat(ctx context.Context, job Job) error {
	kvps := kvpsForJob(job)
	w.log.Debug("starting job heartbeating", kvps...)

	heartbeater := &repeater{
		fn: func(ctx context.Context) error {
			w.log.Debug("attempting to heartbeat job", kvps...)
			err := w.client.Heartbeat(ctx, job)
			if err != nil {
				w.log.WithError(err).Debug("heartbeat attempt error, may retry")
			}
			// Transient heartbeat failures should not stop the heartbeat loop.
			// We don't return an error here so that the repeater continues repeating.
			return nil
		},
		interval: w.heartbeatCfg.interval,
		timeout:  w.heartbeatCfg.timeout,
		opts:     w.retrierCfg.opts(ctx),
	}

	return heartbeater.Do(ctx)
}

func (w *Worker) handle(ctx context.Context, rr ReceiveResult) (err error) {
	start := time.Now()
	defer func() {
		if r := recover(); r != nil {
			w.log.Error("panic in job handler", kvp.String("stack_trace", string(debug.Stack())))
			err = &JobError{
				Source: HandlerErrSource,
				Result: rr,
				Err:    fmt.Errorf("job handler panic: %v", r),
			}
		}

		tags := stats.Tags{"success": strconv.FormatBool(err == nil)}
		w.stats.Counter("job.handler.process.count", tags, 1)
		w.stats.Timing("job.handler.process.time", tags, time.Since(start))
	}()

	w.log.Debug("attempting to execute job handler", kvpsForJob(rr.Job)...)
	if err := w.handler(ctx, rr); err != nil {
		return &JobError{
			Source: HandlerErrSource,
			Result: rr,
			Err:    err,
		}
	}

	return nil
}

func (w *Worker) ack(ctx context.Context, job Job, as AckStatus) error {
	start := time.Now()
	kvps := append(kvpsForJob(job), kvp.String("ack_status", as.String()))
	w.log.Debug("attempting to ack job", kvps...)

	err := w.doWithRetry(ctx, func() error {
		err := w.client.Ack(ctx, job, as)
		if err != nil {
			if ctx.Err() != nil {
				// Context was canceled or timed out,
				// return without an error
				return nil
			}
			w.log.WithError(err).Debug("ack attempt error, may retry")
		}
		return err
	})

	tags := stats.Tags{"ack_status": as.String()}
	w.stats.Timing("job.ack.time", tags, time.Since(start))
	if err == nil {
		w.setIdleStartTime()
		w.stats.Counter("job.ack.count", tags, 1)
	}

	return err
}

func (w *Worker) doWithRetry(ctx context.Context, fn func() error) error {
	return retry.Do(fn, w.retrierCfg.opts(ctx)...)
}
