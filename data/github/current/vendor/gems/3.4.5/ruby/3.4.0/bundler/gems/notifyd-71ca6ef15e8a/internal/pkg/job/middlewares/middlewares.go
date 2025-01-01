// Package middlewares implements middlewares for job processing.
package middlewares

import (
	"context"
	"fmt"
	"sync"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// CtxHandler represents a handler that adds relevant information to the context
type CtxHandler struct {
	ConsumerID string
}

func newCtxHandler(consumerID string) *CtxHandler { return &CtxHandler{consumerID} }

// Handle adds relevant information to the context in order to propagate it through the
// processing of this message. That usually includes things like request_id and hydro relevant
// information.
func (h *CtxHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		ctx = o11y.CtxSetHydroInfo(ctx, h.ConsumerID, req)
		ctx = o11y.CtxSetRequestID(ctx)

		return next.Run(ctx, tenant, logger, req)
	}
}

// LoggerHandler logs that we are processing a message and the result of the process together with
// the elapsed time.
//
// It will use logger.Error in case of error and it will include a request_id and hydro details
// (partition and  offset) in case they are present through the use of logs.AddCtxValues()
type LoggerHandler struct{}

func newLoggerHandler() *LoggerHandler { return &LoggerHandler{} }

// Handle logs that we are processing a message.
func (h *LoggerHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		logger = logger.WithContext(ctx)
		logger.Info("processing message", req.Headers().ToLog()...)

		if err := next.Run(ctx, tenant, logger, req); err != nil {
			logger.WithError(err).WithFields(kvp.Duration("gh.duration_ms", req.Elapsed())).
				Error("message processed with error")
			return err
		}

		logger.WithFields(kvp.Duration("gh.duration_ms", req.Elapsed())).
			Info("message processed")
		return nil
	}
}

// StatsHandler sends some basic metrics about this request to datadog. Those include the status of
// the message processing + error tags that might be relevant and the elapsed time.
type StatsHandler struct {
	Statter stats.Client

	// StatsKey is the key where the stats will be delivered in datadog. By default it is
	// "consumer.handled_message.time"
	StatsKey string
}

const defaultStatsKey string = "consumer.handled_message.time"
const genericStatsKey string = "handler.latency"

func newStatsHandler(statter stats.Client, key string) *StatsHandler {
	if key == "" {
		return &StatsHandler{statter, defaultStatsKey}
	}

	return &StatsHandler{statter, key}
}

// Handle publishers metrics about the request.
func (h *StatsHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		sys := "hydro"
		// For the moment we assume that if there is no topic, it comes directly from Aqueduct
		if topic := req.HydroTopic(ctx); topic == "" {
			sys = "aqueduct"
		}

		s := h.Statter.WithTags(
			stats.Tags{
				"hydro_partition": fmt.Sprintf("%d", req.HydroPartition(ctx)),

				// Semantic Versioning key name
				// @see https://github.com/github/github-telemetry-go/blob/9b03f6e8cb7f1eed10def457a31e17ace090677f/kvp/keys/trace.go#L2001
				"messaging.system": sys,
			},
		)

		if err := next.Run(ctx, tenant, logger, req); err != nil {
			tags := stats.Tags{
				"error_type": errors.FormatAsTag(err),
				"status":     "failed",
			}
			s.DistributionMs(h.StatsKey, tags, req.Elapsed())
			s.DistributionMs(genericStatsKey, tags, req.Elapsed())

			return err
		}

		s.DistributionMs(h.StatsKey, stats.Tags{"status": "succeeded"}, req.Elapsed())
		s.DistributionMs(genericStatsKey, stats.Tags{"status": "succeeded"}, req.Elapsed())
		return nil
	}
}

// PanicHandler catches any panic that might occur during the message processing and makes sure it
// is properly transformed into an error and reports it to Sentry.
//
// Take into account that go-hydro-client's Consume loop already handles panics for us. However it
// does so by recovering from it and then retrying the message. We want to avoid that since we know
// that retried messages might result in duplicated deliveries.
//
// It is meant to run as the innermost handler since its goal is to recover as soon as possible so
// that the rest of the handlers can properly report the message processing.
type PanicHandler struct {
	Reporter exceptions.Reporter
}

func newPanicHandler(reporter exceptions.Reporter) *PanicHandler { return &PanicHandler{reporter} }

// Handle catches panics and publishes to the exception reporter.
func (h *PanicHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) (err error) {
		defer func() {
			if r := recover(); r != nil {
				err = errors.Newf("unhandled panic: %v (%T)", r, r).With(errors.MarkPanic())
				_ = h.Reporter.Report(ctx, err, exceptions.Payload(ctx))
			}
		}()
		return next.Run(ctx, tenant, logger, req)
	}
}

// TenantHandler populates the current tenant and context with information from the incoming request
type TenantHandler struct{}

func newTenantHandler() *TenantHandler {
	return &TenantHandler{}
}

// Handle populates the current tenant and context with information from the incoming request
func (h *TenantHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) (err error) {
		if !tenant.IsMultiTenant() {
			return next.Run(ctx, tenant, logger, req)
		}

		headers := req.Headers()
		tenant, err = tenancy.UpdateFromMap(tenant, headers.IntoMap())
		if err != nil {
			// For the moment we only log and move on.
			// We will have to reject messages once all clients set the headers
			logger.WithContext(ctx).WithError(err).Info("Error extracting tenant information from headers")
		}

		fields := []kvp.Field{}
		if tenant.Slug() != "" {
			ctx = o11y.CtxSetTenantSlug(ctx, tenant.Slug())
			fields = append(fields, kvp.String("gh.tenant", tenant.Slug()))
		}

		if tenant.ID() != 0 {
			fields = append(fields, kvp.Int64("gh.tenant.id", tenant.ID()))
		}

		if len(fields) > 0 {
			logger.WithContext(ctx).Info("Found Tenant in incoming headers", fields...)
		}

		return next.Run(ctx, tenant, logger, req)
	}
}

// DiscardableHandler exists to handle a bug that caused CI runs in GitHub's main app (Dotcom) to
// directly publish Notify messages the main Aqueduct service in production. These messages were
// handled by the Notifyd service in production. Most of the notifications failed due check errors
// but some managed to go out, notifying some users with random data.
//
// To stop the incident, we need to discard any message that was published directly to Aqueduct from
// Dotcom. But we also want to be able to do that kind of publication from different clients.
// To be able to add discard messages that come from the bug but to process the rest, we have into
// account that:
//   - Messages published to Hydro are then replicated to Aqueduct using Aqueduct bridge. These messages
//     always have the "topic" header set.
//   - Messages published from Dotcom with the compromised code don't include the header "topic".
//   - Messages published from Dotcom with the fixed code use the new header "notifyd-message-published-to",
//     indicating that it was, in fact, published by our fixed integration
//
// We can assume that a message that doesn't have a topic and the new header is compromised and thus it
// must be discarded
//
// References
//   - PR that introduced the bug: https://github.com/github/github/pull/229042
//   - PR that fixed the publishing issue: https://github.com/github/github/pull/229527
//   - PR that added the new headers: https://github.com/github/github/pull/229541
type DiscardableHandler struct{}

func newDiscardableHandler() *DiscardableHandler { return &DiscardableHandler{} }

// Handle discards of messages.
func (d *DiscardableHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) (err error) {
		headers := req.Headers()
		if _, ok := headers.Get(job.HeaderPublishedTo); ok {
			return next.Run(ctx, tenant, logger, req)
		}

		// no topic means it comes from aqueduct before the fix that sets the messages
		// headers was released
		if topic := req.HydroTopic(ctx); topic != "" {
			return next.Run(ctx, tenant, logger, req)
		}

		logger.WithContext(ctx).Info("discarding direct aqueduct message")
		return nil
	}
}

// DecompressHandler decompresses any request that has been marked with the header
// "content-encoding" set to a valid compression encoding.
// Check the internal/pkg/compress package to see what compression algorithms we support.
// A client can compress the payload and set this header to reduce a lot of size when
// sending data across services.
// If the header is not set it will continue the chain without decompressing
// If the header has an invalid value it will fail
// More info: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Encoding#directives
type DecompressHandler struct {
	clock clockpkg.Clock
}

func newDecompressHandler(clock clockpkg.Clock) *DecompressHandler {
	return &DecompressHandler{clock}
}

// Handle decompresses the payload of the request if it has been compressed.
func (d *DecompressHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) (err error) {
		logger = logger.WithContext(ctx)
		headers := req.Headers()
		encoding, ok := headers.Get(job.HeaderContentEncoding)
		if !ok {
			logger.Info("found uncompressed message payload")
			return next.Run(ctx, tenant, logger, req)
		}

		start := d.clock.Now()

		inflated, err := compress.Decompress(compress.Encoding(encoding), req.Payload())
		duration := d.clock.Since(start)
		if err != nil {
			return err
		}
		logger.WithFields(
			kvp.Duration("gh.duration_ms", duration),
			kvp.String("gh.notifyd.encoding", encoding),
		).
			Info("uncompressed the message payload")
		req.SetPayload(inflated)

		return next.Run(ctx, tenant, logger, req)
	}
}

// ConcurrentHandler executes small job.Handlers concurrently along with the main job.Handler.
// This is useful when we want to run operations like tracking, analytics, etc, that don't interfere
// with the main job.Handler
// This middleware will wait until all goroutines finish before returning so no concurrent handler
// will be dropped if the main handler is faster.
// If the concurrent goroutines take more than the defined timeout the middleware will return
// without waiting for them to finish.
type ConcurrentHandler struct {
	handlers []job.Handler
	timeout  time.Duration
}

const defaultConcurrentTimeout time.Duration = 30 * time.Second

// NewConcurrentHandler creates a new ConcurrentHandler with the given handlers.
func NewConcurrentHandler(handlers ...job.Handler) *ConcurrentHandler {
	return &ConcurrentHandler{
		handlers: handlers,
		timeout:  defaultConcurrentTimeout,
	}
}

// WithTimeout sets the timeout for the concurrent handlers.
func (c *ConcurrentHandler) WithTimeout(timeout time.Duration) *ConcurrentHandler {
	c.timeout = timeout

	return c
}

// Handle executes the concurrent handlers along with the main handler.
func (c *ConcurrentHandler) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		logger = logger.WithContext(ctx).WithFields(kvp.String("gh.notifyd.ctx", "concurrent-middleware"))
		innerCtx, cancel := context.WithTimeout(ctx, c.timeout)
		defer cancel()

		wg := new(sync.WaitGroup)

		for _, handler := range c.handlers {
			wg.Add(1)
			go func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request, wg *sync.WaitGroup, handler job.Handler) {
				defer wg.Done()

				if err := handler.Run(ctx, tenant, logger, req); err != nil {
					logger.WithError(err).Info("error running concurrent handler")
				}
			}(innerCtx, tenant, logger, req, wg, handler)
		}

		err := next.Run(ctx, tenant, logger, req)

		wg.Wait()

		return err
	}
}

// NewChain returns a chain of middlewares meant to be used by default by our messages
// processors. It handles general things like errors, panics or retries.
func NewChain(
	cfg retries.Config,
	id string,
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	statter stats.Client,
	reporter exceptions.Reporter,
	client aqueduct.Client,
) *job.Chain {
	retrier := retries.NewAqueductRetrier(cfg, clock, telem, client, statter)
	retry := retries.NewMiddleware(retrier, reporter, statter)

	return job.NewChain(
		newCtxHandler(id),
		newLoggerHandler(),
		newStatsHandler(statter, defaultStatsKey),
		newTenantHandler(),
		newDiscardableHandler(),
		newDecompressHandler(clock),
		retry,
		newPanicHandler(reporter),
	)
}
