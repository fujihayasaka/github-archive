package alert

import (
	"strconv"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

type sortID struct{}

func (s sortID) Expression() string {
	return "ts_logical_alerts.id"
}

func (s sortID) SerializedName() string {
	return "id"
}

func (s sortID) SerializedValue(alert *ts.LogicalAlert) string {
	return strconv.FormatUint(uint64(alert.ID), 10)
}

func (s sortID) DeserializeValue(value string) (interface{}, error) {
	id, err := strconv.ParseUint(value, 10, 64)
	return ts.LogicalAlertID(id), err
}

type sortWeight struct{}

func (s sortWeight) Expression() string {
	return "ts_logical_alerts.weight"
}

func (s sortWeight) SerializedName() string {
	return "weight"
}

func (s sortWeight) SerializedValue(alert *ts.LogicalAlert) string {
	return strconv.FormatUint(uint64(alert.Weight), 10)
}

func (s sortWeight) DeserializeValue(value string) (interface{}, error) {
	weight, err := strconv.ParseUint(value, 10, 16)
	return uint16(weight), err
}

type sortUpdatedAt struct{}

func (s sortUpdatedAt) Expression() string {
	return "ts_logical_alerts.updated_at"
}

func (s sortUpdatedAt) SerializedName() string {
	return "updated_at"
}

func (s sortUpdatedAt) SerializedValue(alert *ts.LogicalAlert) string {
	return strconv.FormatInt(alert.UpdatedAt.UTC().UnixMicro(), 10)
}

func (s sortUpdatedAt) DeserializeValue(value string) (interface{}, error) {
	unixMicro, err := strconv.ParseInt(value, 10, 64)
	return sqltime.Time{Time: time.UnixMicro(unixMicro).UTC()}, err
}

type sortNumber struct{}

func (s sortNumber) Expression() string {
	return "ts_logical_alerts.number"
}

func (s sortNumber) SerializedName() string {
	return "number"
}

func (s sortNumber) SerializedValue(alert *ts.LogicalAlert) string {
	return strconv.FormatUint(uint64(alert.Number), 10)
}

func (s sortNumber) DeserializeValue(value string) (interface{}, error) {
	number, err := strconv.ParseUint(value, 10, 32)
	return uint32(number), err
}

type sortLastStateChangeAt struct{}

func (s sortLastStateChangeAt) Expression() string {
	return "MAX(COALESCE(resolved_at, ts_physical_alerts.last_state_change_at))"
}

func (s sortLastStateChangeAt) SerializedName() string {
	return "last_state_change_at_combined"
}

func (s sortLastStateChangeAt) SerializedValue(alert *ts.LogicalAlert) string {
	return strconv.FormatInt(alert.LastStateChangeAt.UTC().UnixMicro(), 10)
}

func (s sortLastStateChangeAt) DeserializeValue(value string) (interface{}, error) {
	unixMicro, err := strconv.ParseInt(value, 10, 64)
	return &sqltime.Time{Time: time.UnixMicro(unixMicro).UTC()}, err
}

// ExtractAlertExpressionSorters converts a proto.AlertSortOrder to a CursorSort.
func ExtractAlertExpressionSorters(order proto.AlertSortOrder) ts.CursorSort[*ts.LogicalAlert] {
	switch order {
	case proto.AlertSortOrder_WEIGHT:
		return ts.CursorSort[*ts.LogicalAlert]{
			Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortWeight{}, sortUpdatedAt{}, sortNumber{}},
			Descending:  true,
		}
	case proto.AlertSortOrder_CREATED_ASCENDING:
		return ts.CursorSort[*ts.LogicalAlert]{
			Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortID{}, sortNumber{}},
			Descending:  false,
		}
	case proto.AlertSortOrder_CREATED_DESCENDING:
		return ts.CursorSort[*ts.LogicalAlert]{
			Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortID{}, sortNumber{}},
			Descending:  true,
		}
	case proto.AlertSortOrder_UPDATED_ASCENDING:
		return ts.CursorSort[*ts.LogicalAlert]{
			Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortLastStateChangeAt{}, sortNumber{}},
			Descending:  false,
		}
	case proto.AlertSortOrder_UPDATED_DESCENDING:
		return ts.CursorSort[*ts.LogicalAlert]{
			Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortLastStateChangeAt{}, sortNumber{}},
			Descending:  true,
		}
	}
	return ts.CursorSort[*ts.LogicalAlert]{
		Expressions: []ts.ExpressionSort[*ts.LogicalAlert]{sortID{}},
		Descending:  false,
	}
}
