// Package delivery handles interactions with ts_deliveries data.
package delivery

import (
	"context"
	"database/sql"
	stderrors "errors" //lint:ignore faillint importing for errors.Join

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"

	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/aws/smithy-go/ptr"
	"github.com/google/uuid"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// Service handles interactions with Deliveries.
type Service struct {
	db                *gorm.DB
	maxLockedDuration time.Duration
}

// DefaultMaxLockedDuration TODO when removing HasCodeScanningInProgressJobsCheck set this to 30 mins
const DefaultMaxLockedDuration = 8 * time.Minute

type Option func(*Service)

func WithMaxLockedDuration(d time.Duration) Option {
	return func(s *Service) {
		s.maxLockedDuration = d
	}
}

// NewService creates a delivery service with the given parameters
func NewService(db *gorm.DB, opts ...Option) *Service {
	as := &Service{
		db:                db,
		maxLockedDuration: DefaultMaxLockedDuration,
	}
	for _, opt := range opts {
		opt(as)
	}
	return as
}

// CreateDelivery saves the delivery.
func (s *Service) CreateDelivery(ctx context.Context, delivery *ts.Delivery) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// try and load the id from the database if the record already exists
	// there is a race condition here because we do not have a unique key on this table, however in practice
	// because this is being called from a hydro worker that is partitioned on repository ID it is unlikely to be an issue
	err := db.
		Model(ts.Delivery{}).
		Where("repository_id = ? AND sarif_id = ?", delivery.RepositoryID, delivery.SarifID).
		Order("created_at DESC").
		Limit(1).
		Select("id").
		Row().
		Scan(&delivery.ID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}

	return errors.Wrap(db.Save(&delivery).Error, "failed to update delivery")
}

func (s *Service) GetDeliveriesByWorkflowRunID(ctx context.Context, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID) ([]ts.Delivery, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var deliveries []ts.Delivery
	err := db.Model(&ts.Delivery{}).
		Where("repository_id = ? AND workflow_run_id = ?", repoID, workflowRunID).
		Find(&deliveries).Error

	return deliveries, err
}

// CompleteDelivery marks the delivery as complete.
func (s *Service) CompleteDelivery(ctx context.Context, d *ts.Delivery) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	d.Complete = true

	now := gorm.NowFunc()

	d.ProcessingCompletedAt = &now

	if err := db.Save(d).Error; err != nil {
		return errors.Wrapf(err, "failed to save delivery (%d)", d.ID)
	}

	return nil
}

var ErrDeliveryLocked = errors.New("delivery locked by another worker")
var ErrDeliveryNotCompleted = errors.New("delivery not completed after successful processing")

func incompleteScope(db *gorm.DB) *gorm.DB {
	return db.Where(`complete = 0 AND processing_started_at IS NOT NULL`)
}

func (s *Service) NextDelivery(ctx context.Context, repositoryID ts.RepositoryEID) (*ts.Delivery, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var delivery ts.Delivery

	// find the next delivery that is eligible for processing
	err := db.Model(ts.Delivery{}).
		Where("repository_id = ?", repositoryID).
		Scopes(incompleteScope).
		// If there is already a locked delivery we should always return that one first
		Order("processing_lock DESC, created_at ASC").
		Limit(1).
		Find(&delivery).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "no available delivery")
	}

	return &delivery, nil
}

// WithLockedDelivery attempts to find an incomplete delivery, lock it and then call fn to do some work on the delivery.
// If no deliveries are available it will do nothing.
// If a delivery was available but already locked it will return ErrDeliveryLocked.
// If a delivery is locked but has been processing for more than n minutes then it will re-lock the delivery and call fn.
func (s *Service) WithLockedDelivery(ctx context.Context, delivery *ts.Delivery, fn func(context.Context) error) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if delivery.ProcessingLock != nil {
		// if it looks like this delivery might be stuck (it has been processing for more than n minutes)
		// then continue on and attempt to acquire the lock below, otherwise return ErrDeliveryLocked
		lockDuration := time.Since(delivery.UpdatedAt.Time)

		if lockDuration < s.maxLockedDuration {
			return ErrDeliveryLocked
		}
		previousJobID := ""
		if delivery.JobID != nil {
			previousJobID = *delivery.JobID
		}
		appctx.Logger(ctx).Info("overriding lock", delivery.ID.AsKVP(), kvp.Duration("gh.turboscan.delivery_lock_duration", lockDuration), kvp.String("gh.aqueduct.previous_job_id", previousJobID))
		appctx.Stats(ctx).Counter("delivery.lock_override", stats.Tags{}, 1)
		appctx.Stats(ctx).Timing("delivery.lock_override_duration", stats.Tags{}, lockDuration)
	}

	processingLock := ptr.String(uuid.NewString())

	query := db.Model(ts.Delivery{}).Where("id = ? AND repository_id = ?", delivery.ID, delivery.RepositoryID).Scopes(incompleteScope)
	// attempt to get the lock with a compare and swap, using the previous value if available
	if delivery.ProcessingLock == nil {
		query = query.Where("processing_lock IS NULL")
	} else {
		// we are re-acquiring a lock for a record that is stuck
		query = query.Where("processing_lock = ?", delivery.ProcessingLock)
	}

	var jobID *string
	if id, ok := ctx.Value(aqueduct.JobIDKey).(string); ok {
		jobID = &id
	} else {
		appctx.Logger(ctx).Error("failed to get job id from context")
	}
	query = query.UpdateColumns(map[string]interface{}{"processing_lock": processingLock, "job_id": jobID, "updated_at": sqltime.Now()})

	if err := query.Error; err != nil {
		return errors.Wrap(err, "failed to lock delivery record")
	}

	if query.RowsAffected == 0 {
		// another worker beat us to it
		return ErrDeliveryLocked
	}

	// make the record match the new database state
	delivery.ProcessingLock = processingLock
	delivery.JobID = jobID

	funcErr := fn(ctx)

	var incompleteError error
	// We will only accept an incomplete delivery here if there was an error
	if funcErr == nil && !delivery.Complete {
		incompleteError = ErrDeliveryNotCompleted
	}

	// unlock the delivery now the record has been processed
	unlockErr := db.
		Model(ts.Delivery{}).
		Where("id = ? AND processing_lock = ? AND repository_id = ?", delivery.ID, delivery.ProcessingLock, delivery.RepositoryID).
		UpdateColumn("processing_lock", nil).
		Error

	return stderrors.Join(funcErr, unlockErr, incompleteError)
}

func (s *Service) GetDelivery(ctx context.Context, repositoryID ts.RepositoryEID, sarifID ts.SarifID) (*ts.Delivery, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	delivery := ts.Delivery{
		RepositoryID: repositoryID,
		SarifID:      sarifID,
	}

	if err := db.Where(&delivery).First(&delivery).Error; err != nil {
		return nil, errors.Wrap(err, "failed to get delivery")
	}

	return &delivery, nil
}
