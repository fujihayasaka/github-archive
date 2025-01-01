package alert

import (
	"github.com/github/turboscan/ts/proto"
)

// SortBy converts a proto.AlertSortOrder to an SQL ORDER BY fragment.
// This method is kept for compatibility until we switch to entirely using
// the cursor-based pagination.
func SortBy(order proto.AlertSortOrder) string {
	switch order {
	case proto.AlertSortOrder_WEIGHT:
		return "ts_logical_alerts.weight desc, ts_logical_alerts.updated_at desc, number desc"
	case proto.AlertSortOrder_CREATED_ASCENDING:
		return "ts_logical_alerts.id asc, number asc"
	case proto.AlertSortOrder_CREATED_DESCENDING:
		return "ts_logical_alerts.id desc, number desc"
	case proto.AlertSortOrder_UPDATED_ASCENDING:
		return "MAX(COALESCE(resolved_at, ts_physical_alerts.last_state_change_at)) asc, number asc"
	case proto.AlertSortOrder_UPDATED_DESCENDING:
		return "MAX(COALESCE(resolved_at, ts_physical_alerts.last_state_change_at)) desc, number desc"
	}
	return ""
}
