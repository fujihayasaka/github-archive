package jobs

import (
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/delivery_processor"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

type ProcessDelivery struct {
	RepoID  ts.RepositoryEID
	Attempt int
}

var _ aqueduct.EnqueableJob = (*ProcessDelivery)(nil)

func (p ProcessDelivery) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepoID
}

func (p ProcessDelivery) Name() string {
	return "ProcessDelivery"
}

func (p ProcessDelivery) Queue() string {
	return "turboscan-process-delivery"
}

func (p ProcessDelivery) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (p ProcessDelivery) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	startTime := time.Now()
	defer func() {
		duration := time.Since(startTime)
		appctx.Stats(ctx).DistributionMs("process_delivery.job_duration", stats.Tags{}, duration)
		appctx.Logger(ctx).WithFields(kvp.Float64("gh.operation.duration", float64(duration))).Info("Processed delivery")
	}()

	if s == nil || s.DeliveryProcessor == nil || s.Aqueduct == nil {
		return errors.New("missing required services")
	}
	return p.perform(ctx, s.DeliveryProcessor, s.Aqueduct)
}

func (p ProcessDelivery) perform(ctx context.Context, d aqueduct.DeliveryProcessor, aq aqueduct.JobPerformer) error {
	logger := appctx.Logger(ctx)
	if p.RepoID == 0 {
		return errors.New("repository ID not set")
	}

	err := d.ProcessDeliveries(ctx, p.RepoID, p.Attempt)

	if errors.Is(err, delivery_processor.ErrContextCancelled) {
		// there was more work to do but context was cancelled so return error to trigger aqueduct handler retry logic
		return err
	}

	if errors.Is(err, delivery_processor.ErrMoreDeliveries) {
		// there was more work to do, but we wanted to let another job have a go
		// queue the extra work for later
		appctx.Stats(ctx).Counter("process_delivery.max_deliveries_exceeded", stats.Tags{}, 1)
		logger.Info("MaxDeliveries exceeded for repo", p.RepoID.AsKVP())
		_, err := aq.PerformLater(ctx, ProcessDelivery{
			RepoID: p.RepoID,
		})
		return err
	}

	var errTryAgain *delivery_processor.ErrTryAgainLater
	if errors.As(err, &errTryAgain) {
		// something went wrong that might work if we tried again
		_, jobErr := aq.PerformLaterAt(ctx, ProcessDelivery{
			RepoID:  p.RepoID,
			Attempt: errTryAgain.Attempt,
		}, time.Now().Add(errTryAgain.After))

		appctx.Stats(ctx).Counter("process_delivery.retry_on_error", stats.Tags{}, 1)
		logger.WithError(errTryAgain).Error(errors.Wrap(err, "error while processing delivery").Error(), p.RepoID.AsKVP())
		return stderrors.Join(err, jobErr)
	}

	if err != nil {
		// there was an error working through the backlog and we have given up
		logger.WithError(err).Error("Giving up processing Deliveries", p.RepoID.AsKVP())
		appctx.Stats(ctx).Counter("process_delivery.max_retries_exceeded", stats.Tags{}, 1)
		return err
	}

	return nil
}
