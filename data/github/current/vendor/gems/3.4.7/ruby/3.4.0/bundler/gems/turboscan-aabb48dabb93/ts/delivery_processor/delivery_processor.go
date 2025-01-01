// Package delivery_processor provides a wrapper around the New Analysis Processor for aqueduct processing of deliveries.
package delivery_processor

import (
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"fmt"
	"time"

	"github.com/olivere/elastic"

	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/o11y"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type Processor interface {
	ProcessNewDelivery(context.Context, *ts.Delivery) ([]*ts.Analysis, error)
}

type AnalysisPublisher interface {
	ProcessedAnalysis(context.Context, *tshydro.Analysis) error
	FailedAnalysis(context.Context, *tshydro.Analysis) error
}

// StatusService is used as an interface for enabled_status.EnabledStatusService
type StatusService interface {
	PublishStatusIfChanged(context.Context, ts.RepositoryEID, ts.EnablementReason, []byte, *bool)
}

type DeliveryProcessor struct {
	deliveryService DeliveryService
	processor       Processor
	publisher       AnalysisPublisher
	statusService   StatusService
	deadline        time.Duration
}

func NewDeliveryProcessor(deliveryService DeliveryService, p Processor, pub AnalysisPublisher, s StatusService, deadline time.Duration) *DeliveryProcessor {
	return &DeliveryProcessor{
		deliveryService: deliveryService,
		processor:       p,
		publisher:       pub,
		statusService:   s,
		deadline:        deadline,
	}
}

var ErrContextCancelled = errors.New("job completed but context cancelled while more deliveries available")
var ErrMoreDeliveries = errors.New("job completed but more deliveries available")
var ErrSameDelivery = errors.New("delivery processor tried to re-process the same delivery")

// ErrTryAgainLater hints that there was a transient error during processing that may be resolved by trying again later.
type ErrTryAgainLater struct {
	After   time.Duration
	Attempt int
}

func (e *ErrTryAgainLater) Error() string {
	return fmt.Sprintf("try delivery again after %s", e.After)
}

func (e *ErrTryAgainLater) Is(err error) bool {
	var target *ErrTryAgainLater
	return errors.As(err, &target)
}

func (p *DeliveryProcessor) ProcessDeliveries(ctx context.Context, repoID ts.RepositoryEID, attempt int) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	started := time.Now()

	var previousD *ts.Delivery
	var errSameDelivery error
	for {
		d, err := p.deliveryService.NextDelivery(ctx, repoID)
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// no more work to do
			break
		}
		if err != nil {
			return errors.Wrap(err, "failed to fetch delivery")
		}

		// once we are looping it here should not be possible we receive the same delivery twice
		if previousD != nil && d.ID == previousD.ID {
			errSameDelivery = ErrSameDelivery
			appctx.Stats(ctx).Counter("aqueduct.delivery_processor.same_delivery_errors", stats.Tags{}, 1)
			appctx.Logger(ctx).WithError(errSameDelivery).Error("attempted to process same delivery twice in a row", d.ID.AsKVP())
			// we handle this error in the processing block to re-use the backoff/retry logic
		} else {
			errSameDelivery = nil
		}
		// set the previous delivery after the error check
		previousD = d

		// If context cancelled with more deliveries, break out of loop
		if ctx.Err() != nil {
			return ErrContextCancelled
		}
		// allow the job to continue to process deliveries until it is time to let another job have a go
		if time.Since(started) > p.deadline {
			return ErrMoreDeliveries
		}

		if err := p.deliveryService.WithLockedDelivery(ctx, d, func(ctx context.Context) error {
			var analyses []*ts.Analysis
			var innerErr error

			// don't re-process the same delivery twice in loop, let the backoff logic engage
			if errSameDelivery == nil {
				analyses, innerErr = p.processDelivery(ctx, d)
				if innerErr == nil {
					// successful processing, continue
					return nil
				}
			}

			backoff, retry := elastic.NewExponentialBackoff(10*time.Second, 5*time.Minute).Next(attempt)

			var pe *ts.ProcessError
			isProcessError := errors.As(innerErr, &pe)
			if isProcessError || !retry {
				// either the error is fatal or we are not planning on retrying this delivery
				// ensure that the delivery has been completed so that it will not be picked up again
				if !d.Complete {
					d.Failed = true
					if saveErr := p.deliveryService.CompleteDelivery(ctx, d); saveErr != nil {
						// if this save call fails the same delivery will be picked up on the next time round the loop
						// this is ok, hopefully we manage to save it if it fails next time
						return stderrors.Join(innerErr, errors.Wrap(saveErr, "failed to complete delivery"))
					}
				}

				// it is possible for this call to fail, in which case the job will not be retried
				// and we will never emit a FailedAnalysis for the delivery
				publishErr := p.publisher.FailedAnalysis(ctx, CreateReturnMessage(analyses, d))
				if publishErr != nil {
					return stderrors.Join(innerErr, errors.Wrap(publishErr, "error publishing FailedAnalysis"))
				}

				return innerErr
			}

			// this wasn't a processing error. it is possible that trying the job again would succeed
			return stderrors.Join(innerErr, errSameDelivery, &ErrTryAgainLater{
				After:   backoff,
				Attempt: attempt + 1,
			})
		}); err != nil {
			// If we cannot obtain a lock then a different worker is processing this delivery
			if errors.Is(err, delivery.ErrDeliveryLocked) {
				break
			}

			appctx.Stats(ctx).Counter("aqueduct.delivery_processor.errors", stats.Tags{}, 1)

			if errors.Is(err, &ErrTryAgainLater{}) {
				// break out of processing and allow a new job to be scheduled to re-attempt this delivery
				return err
			}

			if !d.Complete {
				// there was an error we did not know how to handle and the delivery was not completed
				// we have to stop work and pass control back to the job
				// if this happens it probably indicates a bug that needs fixing
				appctx.Stats(ctx).Counter("aqueduct.delivery_processor.fatal_errors", stats.Tags{}, 1)
				appctx.Logger(ctx).WithError(err).Error("gave up processing deliveries", d.ID.AsKVP(), repoID.AsKVP())
				return err
			}

			// despite the error the delivery is complete. we do not want to try this delivery again
			// return nil and proceed to the next delivery
			// if for any reason complete was not really updated in the database then this delivery will
			// be selected again in the next iteration
			appctx.Logger(ctx).WithError(err).Error("ignoring delivery error and continuing", d.ID.AsKVP(), repoID.AsKVP())
		}

		// we made progress so reset attempts back to zero to give future deliveries the same number of chances
		attempt = 0
	}

	return nil
}

func (p *DeliveryProcessor) processDelivery(ctx context.Context, d *ts.Delivery) ([]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	taggedStatsClient := taggedStatsClient(ctx, d)

	ctx = flipper.StoreLimitAlertFixesInContext(ctx, d.RepositoryID)

	analyses, err := p.processor.ProcessNewDelivery(ctx, d)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error(errorProcessingDelivery)
		statsProcessDuration(taggedStatsClient, stats.Tags{"success": "false"}, d)
		return analyses, errors.Wrap(err, errorProcessingDelivery)
	}

	successTags := stats.Tags{"success": "true"}
	statsProcessDuration(taggedStatsClient, successTags, d)
	taggedStatsClient.Counter("newanalysis.status", successTags, 1)

	// We return the identical message with the Tools section filled in
	returnMessage := CreateReturnMessage(analyses, d)

	// Note: We get the original message as input to this method, but we
	// might want to specialize the ProcessedAnalysis message in the
	// future to contain different information and simplify this function signature.
	err = p.publisher.ProcessedAnalysis(ctx, returnMessage)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error(errorProducingProcessedAnalysis, d.RepositoryID.AsKVP())
		return analyses, errors.Wrap(err, errorProducingProcessedAnalysis)
	}

	if len(analyses) > 0 {
		possibleStatus := !d.MarksAsOutdated()
		p.statusService.PublishStatusIfChanged(ctx, d.RepositoryID, ts.EnablementReason_RECEIVED_ANALYSIS, d.Ref, &possibleStatus)
	}

	return analyses, nil
}

const (
	errorProcessingDelivery         = "error processing Delivery"
	errorProducingProcessedAnalysis = "error producing ProcessedAnalysis"
)

func taggedStatsClient(ctx context.Context, d *ts.Delivery) stats.Client {
	if d.RepositoryNWO.HasOwner("dsp-testing") {
		return appctx.Stats(ctx).WithTags(stats.Tags{"owner": "dsp-testing"})
	}
	return appctx.Stats(ctx)
}

func statsProcessDuration(s stats.Client, t stats.Tags, d *ts.Delivery) {
	if d.ProcessingStartedAt != nil {
		s.DistributionMs("newanalysis.processing_duration_part", stats.Tags{"stage": "aqueduct"}, time.Since(*d.ProcessingStartedAt))
	}
	if d.HydroEnqueuedAt != nil {
		s.DistributionMs("newanalysis.processing_duration", t, time.Since(*d.HydroEnqueuedAt))
	}
}

func CreateReturnMessage(analyses []*ts.Analysis, d *ts.Delivery) *tshydro.Analysis {
	tools := make([]*tshydro.Analysis_Tool, len(analyses))
	for idx, a := range analyses {
		tools[idx] = &tshydro.Analysis_Tool{
			Name:   a.Tool.CanonicalName.String(),
			ToolId: uint64(a.Tool.ID),
		}
	}

	outdatedConfiguration := &tshydro.Analysis_OutdatedConfiguration{}
	if d.MarksAsOutdated() {
		outdatedConfiguration.ToolName = d.OutdatedConfiguration.ToolName.String()
		outdatedConfiguration.Category = d.OutdatedConfiguration.Category.String()
	}

	msg := &tshydro.Analysis{
		RepositoryId:       uint64(d.RepositoryID),
		SarifUri:           d.SarifPath,
		CommitOid:          d.CommitOid.String(),
		Ref:                d.Ref,
		Environment:        d.Environment.String(),
		CheckoutUri:        d.CheckoutURI.String(),
		WorkflowRunId:      uint64(d.WorkflowRunID),
		WorkflowRunAttempt: int64(d.WorkflowRunAttempt),
		AnalysisKey:        d.AnalysisKey.String(),

		RequestId:             d.RequestID.String(),
		RepoNwo:               d.RepositoryNWO.String(),
		OwnerId:               uint64(d.OwnerID),
		CheckRunIds:           d.CheckRunIds,
		SourceRepositoryId:    uint64(d.SourceRepositoryID),
		Tools:                 tools,
		SarifId:               d.SarifID.String(),
		OutdatedConfiguration: outdatedConfiguration,
		TrackStatus:           d.TrackStatus,
	}

	if d.BuildStartedAt != nil {
		msg.BuildStartAt = timestamppb.New(*d.BuildStartedAt)
	}
	if d.UploadStartedAt != nil {
		msg.UploadStartedAt = timestamppb.New(*d.UploadStartedAt)
	}
	if d.UploadFinishedAt != nil {
		msg.UploadFinishedAt = timestamppb.New(*d.UploadFinishedAt)
	}
	if d.HydroEnqueuedAt != nil {
		msg.HydroEnqueuedAt = timestamppb.New(*d.HydroEnqueuedAt)
	}

	return msg
}
