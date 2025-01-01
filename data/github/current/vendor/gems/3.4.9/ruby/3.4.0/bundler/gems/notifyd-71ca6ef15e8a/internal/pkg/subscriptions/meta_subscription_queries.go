package subscriptions

import (
	"fmt"
	"strconv"

	sql "github.com/Masterminds/squirrel"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/pagination"
)

type metaSubscriptionQueries struct {
	telem *telemetry.Provider
}

const paginationID = "s.id"

func newMetaSubscriptionQueries(telem *telemetry.Provider) metaSubscriptionQueries {
	return metaSubscriptionQueries{telem: telem}
}

func (q metaSubscriptionQueries) insert(subscriptions []*MetaSubscription) sql.Sqlizer {
	query := sql.Insert("meta_subscriptions").
		Columns("user_id", "name", "details", "created_at", "updated_at")

	for _, subscription := range subscriptions {
		query = query.Values(
			subscription.UserID,
			subscription.Name,
			// SubsciptionDetails implements sql/driver.Valuer interface, so it will be automatically converted
			subscription.Details,
			subscription.CreatedAt,
			subscription.UpdatedAt,
		)
	}

	return query
}

func (q metaSubscriptionQueries) deleteByIDs(subscriptionIDs []int64) sql.Sqlizer {
	return sql.Delete("meta_subscriptions").Where(sql.Eq{"id": subscriptionIDs})
}

// find selects meta subscriptions based on a combination of userID and custom fields.
// Both arguments may be empty (indicated through their zero values).
func (q metaSubscriptionQueries) find(userID int64, fields []CustomField, page pagination.Page) sql.Sqlizer {
	query := sql.Select(
		"s.id AS id",
		"s.user_id AS user_id",
		"s.name AS name",
		"s.details AS details",
		"s.updated_at AS updated_at",
		"s.created_at AS created_at",
	).From("meta_subscriptions AS s")

	for i := range fields {
		query = query.Join(fmt.Sprintf("subscription_custom_fields AS cf%d ON s.id = `cf%d`.meta_id AND s.user_id = `cf%d`.user_id", i, i, i))
	}
	var filter sql.And
	for i, field := range fields {
		filter = append(filter, sql.Eq{fmt.Sprintf("cf%d.name", i): field.Name})
		if field.Value != "" {
			filter = append(filter, sql.Eq{fmt.Sprintf("cf%d.value", i): field.Value})
		}
	}
	if userID > 0 {
		filter = append(filter, sql.Eq{"s.user_id": userID})
	}
	query = query.Where(filter)
	return page.ApplyToAnyQuery(query, applyCursorQuery, applyOrderBy, applyLimit)
}

func applyCursorQuery(query sql.SelectBuilder, page pagination.Page) sql.SelectBuilder {
	stringID := pagination.DecodeCursor(page.Cursor())
	id, _ := strconv.ParseInt(stringID, 10, 64)

	// if we have a cursor, add it as a where clause
	if id > 0 {
		query = query.Where(sql.Gt{paginationID: id})
	}
	return query
}

func applyOrderBy(query sql.SelectBuilder, page pagination.Page) sql.SelectBuilder {
	// cursor-based pagination requires an order by clause
	return query.OrderBy(paginationID + " ASC")
}

func applyLimit(query sql.SelectBuilder, page pagination.Page) sql.SelectBuilder {
	// if we have a limit, set it or fallback to the upper limit
	if page.Limit() > 0 {
		return query.Suffix("LIMIT ?", int(min(page.Limit(), MaximumRequestPageLimit)))
	}
	return query.Suffix("LIMIT ?", MaximumRequestPageLimit)
}
