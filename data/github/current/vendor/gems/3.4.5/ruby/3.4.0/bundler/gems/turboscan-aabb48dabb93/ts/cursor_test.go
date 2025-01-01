package ts

import (
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

type testObj struct {
	X uint64
	Y uint64
}

type testSortX struct{}

func (s testSortX) Expression() string {
	return "mytable.myfield"
}

func (s testSortX) SerializedName() string {
	return "myfield"
}

func (s testSortX) SerializedValue(x testObj) string {
	return strconv.FormatUint(x.X, 10)
}

func (s testSortX) DeserializeValue(value string) (interface{}, error) {
	id, err := strconv.ParseUint(value, 10, 64)
	return id, err
}

type testSortY struct{}

func (s testSortY) Expression() string {
	return "myothertable.myotherfield"
}

func (s testSortY) SerializedName() string {
	return "myotherfield"
}

func (s testSortY) SerializedValue(x testObj) string {
	return strconv.FormatUint(x.Y, 10)
}

func (s testSortY) DeserializeValue(value string) (interface{}, error) {
	id, err := strconv.ParseUint(value, 10, 64)
	return id, err
}

var testCursorSort = CursorSort[testObj]{
	Expressions: []ExpressionSort[testObj]{testSortX{}, testSortY{}},
	Descending:  false,
}

var testDecendingSort = CursorSort[testObj]{
	Expressions: []ExpressionSort[testObj]{testSortX{}, testSortY{}},
	Descending:  true,
}

func TestCursorSerialization(t *testing.T) {
	expected := Cursor{"abc": "def", "123": "456"}
	other := Cursor{"abc": "def", "123": "789"}

	enc, err := EncodeCursor(expected)
	require.NoError(t, err)
	otherEnc, err := EncodeCursor(other)
	require.NoError(t, err)
	require.NotEqual(t, enc, otherEnc)

	actual, err := DecodeCursor(enc)
	require.NoError(t, err)
	require.Equal(t, expected, actual)
}

func TestCursorDecodeErrorNoBase64(t *testing.T) {
	_, err := DecodeCursor("{}")
	require.Error(t, err)
}

func TestCursorDecodeErrorNoJson(t *testing.T) {
	_, err := DecodeCursor("e2FiYzEyMywge2RlZjQ1Ng==") // Encoded "{abc123, {def456"
	require.Error(t, err)
}

func TestBuildCursor(t *testing.T) {
	cursor := testCursorSort.BuildCursor(testObj{X: 123, Y: 456})
	require.Len(t, cursor, 2)
	require.Equal(t, "123", cursor["myfield"])
	require.Equal(t, "456", cursor["myotherfield"])
}

func TestOrderBy(t *testing.T) {
	order := testCursorSort.OrderBy()
	require.Equal(t, "mytable.myfield ASC, myothertable.myotherfield ASC", order)

	order = testDecendingSort.OrderBy()
	require.Equal(t, "mytable.myfield DESC, myothertable.myotherfield DESC", order)
}

func TestFilterBy(t *testing.T) {
	cursor := testCursorSort.BuildCursor(testObj{X: 123, Y: 456})
	filter, err := testCursorSort.FilterBy(cursor)
	require.NoError(t, err)
	require.Len(t, filter, 2)
	require.Equal(t, "mytable.myfield > ?", filter[0].Expression)
	require.Equal(t, uint64(123), filter[0].Value)
	require.Equal(t, "myothertable.myotherfield > ?", filter[1].Expression)
	require.Equal(t, uint64(456), filter[1].Value)

	filter, err = testDecendingSort.FilterBy(cursor)
	require.NoError(t, err)
	require.Len(t, filter, 2)
	require.Equal(t, "mytable.myfield < ?", filter[0].Expression)
	require.Equal(t, uint64(123), filter[0].Value)
	require.Equal(t, "myothertable.myotherfield < ?", filter[1].Expression)
	require.Equal(t, uint64(456), filter[1].Value)
}

func TestFilterBySpuriousFields(t *testing.T) {
	// Completely empty cursor
	cursor := Cursor{"abc": "def", "123": "456"}
	filter, err := testCursorSort.FilterBy(cursor)
	require.NoError(t, err)
	require.Len(t, filter, 0)

	// Spurious fields and real fields
	cursor = Cursor{"myfield": "123", "abc": "def"}
	filter, err = testCursorSort.FilterBy(cursor)
	require.NoError(t, err)
	require.Len(t, filter, 1)
	require.Equal(t, "mytable.myfield > ?", filter[0].Expression)

	// Broken values
	cursor = Cursor{"myfield": "abc"}
	_, err = testCursorSort.FilterBy(cursor)
	require.Error(t, err)
}
