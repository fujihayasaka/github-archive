package alert

import (
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestConversion(t *testing.T) {
	stateChangedAt := sqltime.Now()
	alert := &ts.LogicalAlert{
		BaseModel:         ts.BaseModel{UpdatedAt: sqltime.Now()},
		ID:                42,
		Weight:            12,
		Number:            1,
		LastStateChangeAt: &stateChangedAt,
	}
	requireConversion(t, sortID{}, alert, alert.ID)
	requireConversion(t, sortWeight{}, alert, alert.Weight)
	requireConversion(t, sortUpdatedAt{}, alert, alert.UpdatedAt)
	requireConversion(t, sortNumber{}, alert, alert.Number)
	requireConversion(t, sortLastStateChangeAt{}, alert, alert.LastStateChangeAt)
}

func requireConversion(t *testing.T, s ts.ExpressionSort[*ts.LogicalAlert], alert *ts.LogicalAlert, expected interface{}) {
	t.Helper()
	serialized := s.SerializedValue(alert)
	deserialized, err := s.DeserializeValue(serialized)
	require.NoError(t, err)
	require.Equal(t, expected, deserialized)
}
