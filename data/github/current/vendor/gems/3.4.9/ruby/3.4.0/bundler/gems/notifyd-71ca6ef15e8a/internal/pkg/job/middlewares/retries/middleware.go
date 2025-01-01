package retries

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Middleware backs a hydro request handler middleware
type Middleware struct {
	retrier  Retrier
	reporter exceptions.Reporter
	statter  stats.Client
}

// NewMiddleware creates a new Middleware
func NewMiddleware(retrier Retrier, reporter exceptions.Reporter, statter stats.Client) *Middleware {
	return &Middleware{retrier: retrier, reporter: reporter, statter: statter}
}

// Handle returns a middleware handler function
func (m *Middleware) Handle(next job.Handler) job.HandlerFunc {
	return func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
		logger = logger.WithContext(ctx).WithFields(kvp.String("gh.notifyd.ctx", "retries-middleware"))

		err := next.Run(ctx, tenant, logger, req)

		// If an error has been returned, then make sure it is retried.
		if err != nil && errors.IsRetriable(err) {
			logger.Info("retrying message after failure")
			m.retry(ctx, tenant, logger, req)
			return err
		}

		// When it is not retriable we just propagate it
		if err != nil {
			logger.Info("error is non retriable")
			return err
		}

		// Otherwise report the proper stats.
		var envelope hydro_pb.Envelope
		err = proto.Unmarshal(req.Payload(), &envelope)
		if err != nil {
			return errors.Wrap(err, "unmarshalling hydro envelope")
		}

		msg, err := retriables.BuildMessage(&envelope)
		if err != nil {
			return err
		}

		if msg.GetAttempts() > 0 {
			logger.WithFields(kvp.Int("gh.notifyd.retry.attempts", int(msg.GetAttempts()))).Info("succeeded after retry")
			statsCount(m.statter, msg, statsProcessed, statsSuccess)
		}

		return nil
	}
}

func (m *Middleware) retry(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) {
	defer func() {
		if r := recover(); r != nil {
			err := errors.Newf("unhandled panic: %v (%T)", r, r).With(errors.MarkPanic())
			_ = m.reporter.Report(ctx, err, exceptions.Payload(ctx))
		}
	}()

	if err := m.retrier.Retry(ctx, tenant, req.Payload()); err != nil {
		logger.WithContext(ctx).WithError(err).Error(err.Error())
	}
}
