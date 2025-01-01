package routing

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
)

// MaximumRequestPageLimit is the maximum number of routing settings that can be returned in a single Get request
const MaximumRequestPageLimit = 1000

// SettingsService provides CRUD like operations for routing settings.
type SettingsService interface {
	BatchCreateAndDelete(ctx context.Context, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error)
	GetSettings(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error)
	GetSettingsForUsers(ctx context.Context, users []int64, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error)
	BatchReplace(ctx context.Context, userID int64, settingsToCreate []*MetaSetting, fields []CustomField) ([]int64, error)
	Delete(ctx context.Context, userID int64, fields []CustomField) error
}

type settings struct {
	storage Storage
	telem   *telemetry.Provider
	statter stats.Client
}

// NewSettingsService builds a new settings service.
func NewSettingsService(storage Storage, telem *telemetry.Provider, statter stats.Client) SettingsService {
	return settings{
		storage: storage,
		telem:   telem,
		statter: statter,
	}
}

// BatchCreateAndDelete creates subscriptions and delete old ones in bulk
func (s settings) BatchCreateAndDelete(ctx context.Context, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ms, err := s.batchCreateAndDelete(ctx, toCreate, toDelete)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("routing_settings.batch_create_and_delete.time", stats.Tags{"success": success}, time.Since(t0))
	return ms, err
}

func (s settings) batchCreateAndDelete(ctx context.Context, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error) {
	createdRoutingSettings, err := s.storage.BatchCreateAndDelete(ctx, toCreate, toDelete)
	if err != nil {
		return nil, errors.Wrap(err, "batch create and delete settings from database")
	}
	return createdRoutingSettings, nil
}

// BatchReplace deletes routing settings by custom fields and then creates new routing settings for a single user
func (s settings) BatchReplace(ctx context.Context, userID int64, settingsToCreate []*MetaSetting, fields []CustomField) ([]int64, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ids, err := s.batchReplace(ctx, userID, settingsToCreate, fields)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("routing_settings.batch_replace.time", stats.Tags{"success": success}, time.Since(t0))
	return ids, err
}

func (s settings) batchReplace(ctx context.Context, userID int64, settingsToCreate []*MetaSetting, fields []CustomField) ([]int64, error) {
	created, err := s.storage.BatchReplace(ctx, userID, settingsToCreate, fields)
	if err != nil {
		return nil, errors.Wrap(err, "routing settings service batch replace")
	}
	return created, nil
}

func (s settings) Delete(ctx context.Context, userID int64, fields []CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	err := s.storage.Delete(ctx, userID, fields)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("routing_settings.delete.time", stats.Tags{"success": success}, time.Since(t0))
	return err
}

func (s settings) GetSettings(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ms, p, err := s.getSettings(ctx, fields, page)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("routing_settings.get_settings.time", stats.Tags{"success": success}, time.Since(t0))
	return ms, p, err
}

func (s settings) getSettings(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	if page.Limit() > MaximumRequestPageLimit {
		return nil, pagination.NewEmptyStandardPages(), pagination.NewLimitExceededError(MaximumRequestPageLimit, page.Limit())
	}
	return s.storage.GetSettings(ctx, fields, page)
}

func (s settings) GetSettingsForUsers(ctx context.Context, users []int64, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ms, p, err := s.getSettingsForUsers(ctx, users, fields, page)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("routing_settings.get_settings_for_users.time", stats.Tags{"success": success}, time.Since(t0))
	return ms, p, err
}

func (s settings) getSettingsForUsers(ctx context.Context, users []int64, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	if page.Limit() > MaximumRequestPageLimit {
		return nil, pagination.NewEmptyStandardPages(), pagination.NewLimitExceededError(MaximumRequestPageLimit, page.Limit())
	}
	return s.storage.GetSettingsForUsers(ctx, users, fields, page)
}
