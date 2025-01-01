package elasticsearch

import (
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"
)

func TestCursorSerialization(t *testing.T) {
	expectedAlertID := uint64(4)
	expectedUpdatedAt := int64(123)
	otherAlertID := uint64(5)
	otherUpdatedAt := int64(123)

	expected := Cursor{
		AlertID:   &expectedAlertID,
		UpdatedAt: &expectedUpdatedAt,
	}
	other := Cursor{
		AlertID:   &otherAlertID,
		UpdatedAt: &otherUpdatedAt,
	}

	enc, err := EncodeCursor(expected)
	require.NoError(t, err)
	otherEnc, err := EncodeCursor(other)
	require.NoError(t, err)
	require.NotEqual(t, enc, otherEnc)

	actual, err := decodeCursor(enc)
	require.NoError(t, err)
	require.Equal(t, expected, actual)
}

func TestCursorFields(t *testing.T) {
	now := sqltime.Now()
	doc := ts.SearchDocument{
		RepositoryID:    "1",
		AlertID:         42,
		FullDescription: "XSS is bad",
		SarifIdentifier: "js/xss",
		Weight:          12,
		CreatedAt:       &now,
		UpdatedAt:       &now,
	}

	sorts := []proto.AlertSortOrder{
		proto.AlertSortOrder_WEIGHT,
		proto.AlertSortOrder_CREATED_ASCENDING,
		proto.AlertSortOrder_CREATED_DESCENDING,
		proto.AlertSortOrder_UPDATED_ASCENDING,
		proto.AlertSortOrder_UPDATED_DESCENDING,
	}

	for _, sort := range sorts {
		s := ts.SearchSortFromProto(sort)
		c, err := buildCursor(doc, s.Fields)
		require.NoError(t, err)
		require.NotEmpty(t, c)

		fields, err := extractCursorFields(s.Fields, c)
		require.NoError(t, err)
		require.Equal(t, len(fields), len(s.Fields))
	}

}

func TestCursorBackwardsIncompatibility(t *testing.T) {
	// Cursor: {"alert_id":91370176,"updated_at":18446681938112751616}
	_, err := decodeCursor("eyJhbGVydF9pZCI6OTEzNzAxNzYsInVwZGF0ZWRfYXQiOjE4NDQ2NjgxOTM4MTEyNzUxNjE2fQo=")
	require.Error(t, err) // This fails because the cursor contains an uint64 updated_at value which is no longer supported

	// Cursor: {"alert_id":123,"updated_at":-456}
	cursor, err := decodeCursor("eyJhbGVydF9pZCI6MTIzLCJ1cGRhdGVkX2F0IjotNDU2fQo=")
	require.NoError(t, err)
	require.Equal(t, uint64(123), *cursor.AlertID)
	require.Equal(t, int64(-456), *cursor.UpdatedAt)
}
