package subscriptions

import (
	"context"
	"fmt"
	"strings"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/jmoiron/sqlx"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/transaction"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
)

// Storage is the interface for subscription storage.
type Storage interface {
	GetSubscriptions(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error)
	GetSubscriptionsForUser(ctx context.Context, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error)
	BatchReplace(ctx context.Context, userID int64, subscriptionsToCreate []*MetaSubscription, fields []CustomField) ([]int64, error)
	Delete(ctx context.Context, userID int64, fields []CustomField) error
	GetMatchingEntries(ctx context.Context, msgMatchFields notify.MessageMatchFields) ([]*matchengine.MatchedEntry, error)
}

type storage struct {
	clock             clockpkg.Clock
	dbWrite           *sqlx.DB
	dbRead            *sqlx.DB
	telem             *telemetry.Provider
	subscriptions     subscriptionsRepo
	metaSubscriptions metaSubscriptionsRepo
	customFields      customFieldsRepo
	matchRules        matchRulesRepo
	matchingEntries   matchengine.MatchedEntriesRepo
}

// NewStorage creates a new subscription storage.
func NewStorage(clock clockpkg.Clock, telem *telemetry.Provider, db mysql.DB) Storage {
	return &storage{
		clock:             clock,
		dbWrite:           db.Write,
		dbRead:            db.Read,
		telem:             telem,
		subscriptions:     newSubscriptionsRepo(clock, telem),
		metaSubscriptions: newMetaSubscriptionsRepo(clock, telem),
		customFields:      newCustomFieldsRepo(clock, telem),
		matchRules:        newMatchRulesRepo(clock, telem),
		matchingEntries:   matchengine.NewMatchedEntriesRepo(clock, telem),
	}
}

func (s *storage) GetSubscriptions(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return s.metaSubscriptions.get(ctx, s.dbRead, 0, fields, page)
}

func (s *storage) GetSubscriptionsForUser(ctx context.Context, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	if userID == 0 {
		return nil, pagination.NewEmptyStandardPages(), errors.New("non-zero user ID required")
	}
	return s.metaSubscriptions.get(ctx, s.dbRead, userID, fields, page)
}

/*
GetMatchingEntries retrieves entries matching input parameters:

 1. List of topics
 2. Subject type
 3. Trigger
 4. Attributes

Returns a slice of entries matching the provided conditions
*/
func (s *storage) GetMatchingEntries(ctx context.Context, msgMatchFields notify.MessageMatchFields) ([]*matchengine.MatchedEntry, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return s.matchingEntries.Get(ctx, s.dbRead, msgMatchFields)
}

// BatchReplace deletes subscriptions by custom fields and then creates new subscriptions for a single user
func (s *storage) BatchReplace(ctx context.Context, userID int64, newMetaSubscriptions []*MetaSubscription, fields []CustomField) ([]int64, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]int64, error) {
		var ids []int64
		tx := transaction.New()
		err := tx.Run(ctx, s.dbWrite, func(txx *sqlx.Tx) error {
			if err := s.cleanup(ctx, txx, userID, fields); err != nil {
				return err
			}

			metaSubscriptions, err := s.createMetaSubscriptions(ctx, txx, newMetaSubscriptions)
			if err != nil {
				return err
			}

			if err := s.createSubscriptions(ctx, txx, newMetaSubscriptions); err != nil {
				return err
			}

			for _, subscription := range metaSubscriptions {
				ids = append(ids, subscription.ID)
			}

			return nil
		})

		return ids, err
	})
}

// Delete the subscriptions by custom fields.
//
// Deletion is optimized to a single multi-table delete query to avoid the current multiple query transaction.
// NOTE(abeaumont): This is experimental for now, please don't use.
//
//nolint:revive // ignore unhandled error for experimental code
func (s *storage) Delete(ctx context.Context, userID int64, fields []CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	_, err := mysql.WithRetries(ctx, s.clock, s.telem, mysql.ToCallback(func(c context.Context) error {
		if len(fields) == 0 {
			return nil
		}
		// Unfortunately squirrel doesn't have support for multi-table deletions,
		// see https://github.com/Masterminds/squirrel/pull/295.
		var query strings.Builder
		var args []any
		query.WriteString("DELETE ms, s, mr, cf ")
		query.WriteString("FROM meta_subscriptions AS ms ")
		query.WriteString("JOIN subscriptions_v2 AS s ")
		query.WriteString("JOIN subscription_match_rules AS mr ")
		query.WriteString("JOIN subscription_custom_fields AS cf ")
		for i := range fields {
			query.WriteString(fmt.Sprintf("JOIN subscription_custom_fields AS cf%d ", i))
		}
		query.WriteString("WHERE ms.user_id = ? ")
		args = append(args, userID)
		query.WriteString("AND ms.id = `s`.meta_id AND ms.user_id = `s`.user_id ")
		query.WriteString("AND s.id = `mr`.subscription_id ")
		query.WriteString("AND ms.id = `cf`.meta_id AND ms.user_id = `cf`.user_id ")
		for i, field := range fields {
			query.WriteString(fmt.Sprintf("AND ms.id = `cf%d`.meta_id AND ms.user_id = `cf%d`.user_id ", i, i))
			query.WriteString(fmt.Sprintf("AND cf%d.name = ? ", i))
			args = append(args, field.Name)
			if field.Value != "" {
				query.WriteString(fmt.Sprintf("AND cf%d.value = ? ", i))
				args = append(args, field.Value)
			}
		}
		if _, err := s.dbWrite.ExecContext(ctx, query.String(), args...); err != nil {
			return errors.Wrap(err, "deleting")
		}
		return nil
	}))

	return err
}

// cleanup removes all the existing subscriptions and related rows that match the given set of
// custom fields.
func (s *storage) cleanup(ctx context.Context, txx *sqlx.Tx, userID int64, fields []CustomField) error {
	// Should not delete all a user's subscriptions if no custom fields given
	if len(fields) == 0 {
		return nil
	}

	metaIDs, err := s.metaSubscriptions.pluck(ctx, txx, userID, fields)
	if err != nil {
		return err
	}

	if len(metaIDs) == 0 {
		return nil
	}

	subscriptionIDs, err := s.subscriptions.pluck(ctx, txx, metaIDs)
	if err != nil {
		return err
	}

	if err := s.metaSubscriptions.remove(ctx, txx, metaIDs); err != nil {
		return errors.Wrap(err, "delete subscriptions failed")
	}

	if err := s.customFields.remove(ctx, txx, userID, metaIDs); err != nil {
		return err
	}

	if err := s.subscriptions.remove(ctx, txx, subscriptionIDs); err != nil {
		return err
	}

	return s.matchRules.remove(ctx, txx, subscriptionIDs)
}

func (s *storage) createMetaSubscriptions(ctx context.Context, txx *sqlx.Tx, metaSubscriptions []*MetaSubscription) ([]*MetaSubscription, error) {
	autoIncrementStep, err := s.metaSubscriptions.AutoIncrementStep(ctx, txx)
	if err != nil {
		return []*MetaSubscription{}, err
	}

	subscriptions, err := s.metaSubscriptions.insert(ctx, txx, metaSubscriptions, autoIncrementStep)
	if err != nil {
		return []*MetaSubscription{}, err
	}

	return subscriptions, s.customFields.insert(ctx, txx, subscriptions)
}

func (s *storage) createSubscriptions(ctx context.Context, txx *sqlx.Tx, metaSubscriptions []*MetaSubscription) error {
	autoIncrementStep, err := s.subscriptions.AutoIncrementStep(ctx, txx)
	if err != nil {
		return err
	}

	newSubscriptions, err := s.subscriptions.insert(ctx, txx, metaSubscriptions, autoIncrementStep)

	if err != nil {
		return err
	}

	return s.matchRules.insert(ctx, txx, newSubscriptions)
}
