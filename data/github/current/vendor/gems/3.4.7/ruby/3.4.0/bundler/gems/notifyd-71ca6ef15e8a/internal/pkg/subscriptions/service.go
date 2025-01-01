package subscriptions

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
)

// MaximumRequestPageLimit is the maximum number of subscriptions that can be returned in a single Get request
const MaximumRequestPageLimit = 1000

// Service is the interface for the subscription service.
type Service interface {
	GetSubscriptions(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error)
	GetSubscriptionsForUser(ctx context.Context, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error)
	BatchReplace(ctx context.Context, userID int64, subscriptionsToCreate []*MetaSubscription, fields []CustomField) ([]int64, error)
	Delete(ctx context.Context, userID int64, fields []CustomField) error
	GetRecipientsWithReasons(ctx context.Context, msgMatchFields notify.MessageMatchFields) (notify.RecipientIDToReasons, error)
}

// SubscriptionService represents a subscription service.
type SubscriptionService struct {
	storage Storage
	telem   *telemetry.Provider
	statter stats.Client
}

// NewService creates a new subscription service.
func NewService(storage Storage, telem *telemetry.Provider, statter stats.Client) *SubscriptionService {
	return &SubscriptionService{
		storage: storage,
		telem:   telem,
		statter: statter,
	}
}

// GetSubscriptions retrieves subscriptions by custom fields
func (s *SubscriptionService) GetSubscriptions(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ms, p, err := s.getSubscriptions(ctx, fields, page)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("subscriptions.get_subscriptions.time", stats.Tags{"success": success}, time.Since(t0))
	return ms, p, err
}

func (s *SubscriptionService) getSubscriptions(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	if page.Limit() > MaximumRequestPageLimit {
		return nil, pagination.NewEmptyStandardPages(), pagination.NewLimitExceededError(MaximumRequestPageLimit, page.Limit())
	}
	return s.storage.GetSubscriptions(ctx, fields, page)
}

// GetSubscriptionsForUser retrieves subscriptions for specific user and custom fields
func (s *SubscriptionService) GetSubscriptionsForUser(ctx context.Context, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ms, p, err := s.getSubscriptionsForUser(ctx, userID, fields, page)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("subscriptions.get_subscriptions_for_user.time", stats.Tags{"success": success}, time.Since(t0))
	return ms, p, err
}

func (s *SubscriptionService) getSubscriptionsForUser(ctx context.Context, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	if page.Limit() > MaximumRequestPageLimit {
		return nil, pagination.NewEmptyStandardPages(), pagination.NewLimitExceededError(MaximumRequestPageLimit, page.Limit())
	}
	return s.storage.GetSubscriptionsForUser(ctx, userID, fields, page)
}

// BatchReplace deletes subscriptions by custom fields and then creates new subscriptions for a single user
func (s *SubscriptionService) BatchReplace(ctx context.Context, userID int64, subscriptionsToCreate []*MetaSubscription, fields []CustomField) ([]int64, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	ids, err := s.storage.BatchReplace(ctx, userID, subscriptionsToCreate, fields)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("subscriptions.batch_replace.time", stats.Tags{"success": success}, time.Since(t0))
	return ids, err
}

// Delete deletes subscriptions by custom fields
func (s *SubscriptionService) Delete(ctx context.Context, userID int64, fields []CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	err := s.storage.Delete(ctx, userID, fields)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("subscriptions.delete.time", stats.Tags{"success": success}, time.Since(t0))
	return err
}

// GetRecipientsWithReasons retrieves recipients that match the data from notification message
func (s *SubscriptionService) GetRecipientsWithReasons(ctx context.Context, msgMatchFields notify.MessageMatchFields) (notify.RecipientIDToReasons, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	t0 := time.Now()
	success := "true"
	rs, err := s.getRecipientsWithReasons(ctx, msgMatchFields)
	if err != nil {
		success = "false"
	}
	s.statter.DistributionMs("subscriptions.get_recipients_with_reasons.time", stats.Tags{"success": success}, time.Since(t0))
	return rs, err
}

func (s *SubscriptionService) getRecipientsWithReasons(ctx context.Context, msgMatchFields notify.MessageMatchFields) (notify.RecipientIDToReasons, error) {
	matchedEntries, err := s.storage.GetMatchingEntries(ctx, msgMatchFields)
	if err != nil {
		return nil, errors.Wrap(err, "fetching matching entries from database")
	}

	matcher := matchengine.BuildMatcherForSubscriptions(s.telem, msgMatchFields.Attributes)
	matcher.LoadMatchedEntries(matchedEntries)

	return matcher.RecipientReasons(), nil
}
