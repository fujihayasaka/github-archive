package subscriptions

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	querierpkg "github.com/github/notifyd/internal/pkg/mysql/querier"
)

type customFieldsRepo struct {
	querierpkg.Querier
	queries customFieldQueries
	clock   clockpkg.Clock
}

func newCustomFieldsRepo(clock clockpkg.Clock, telem *telemetry.Provider) customFieldsRepo {
	querier := querierpkg.NewRetrier(querierpkg.New(), clock, telem)

	return customFieldsRepo{
		Querier: querier,
		queries: customFieldQueries{},
		clock:   clock,
	}
}

func (r customFieldsRepo) remove(ctx context.Context, store sqlx.ExecerContext, userID int64, metaIDs []int64) error {
	if err := r.Delete(ctx, store, r.queries.deleteByMetaIDs(userID, metaIDs)); err != nil {
		return errors.Wrap(err, "delete subscriptions failed")
	}

	return nil
}

func (r customFieldsRepo) insert(ctx context.Context, store sqlx.ExecerContext, metaSubscriptions []*MetaSubscription) error {
	newFields := []sqlCustomField{}
	for _, meta := range metaSubscriptions {
		for i := range meta.Details.CustomFields {
			field := sqlCustomField{
				UserID:         meta.UserID,
				SubscriptionID: meta.ID,
				Name:           meta.Details.CustomFields[i].Name,
				Value:          meta.Details.CustomFields[i].Value,
			}
			field.UpdateTimestamps(r.clock)

			newFields = append(newFields, field)
		}
	}

	if len(newFields) == 0 {
		return nil
	}

	if _, err := r.Insert(ctx, store, r.queries.insert(newFields)); err != nil {
		return errors.Wrap(err, "inserting custom fields")
	}

	return nil
}
