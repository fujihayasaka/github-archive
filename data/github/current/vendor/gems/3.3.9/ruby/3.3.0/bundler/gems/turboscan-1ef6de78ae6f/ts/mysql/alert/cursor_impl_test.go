package alert

import (
	"context"
	"strconv"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/transforms"
	"github.com/stretchr/testify/require"
)

type testObject struct {
	value int
}

type testFilter struct {
	cursor []ts.SQLCursorFilter
}

func (t *testFilter) SetCursorFilter(filter []ts.SQLCursorFilter) {
	t.cursor = filter
}

type testSort struct{}

func (s testSort) Expression() string {
	return "value"
}

func (s testSort) SerializedName() string {
	return "value"
}

func (s testSort) SerializedValue(x testObject) string {
	return strconv.FormatInt(int64(x.value), 10)
}

func (s testSort) DeserializeValue(value string) (interface{}, error) {
	id, err := strconv.ParseInt(value, 10, 64)
	return int(id), err
}

func TestCursorFetch(t *testing.T) {
	ctx := context.Background()

	sort := ts.CursorSort[testObject]{
		Expressions: []ts.ExpressionSort[testObject]{testSort{}},
		Descending:  false,
	}
	filter := testFilter{}
	opts := &ts.FindOptions{}

	opts.Pagination = &ts.Pagination{Limit: 1}

	// Initial page (page 1)
	opts.Pagination = &ts.Pagination{Limit: 1}
	page1, err := Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Len(t, page1.Results, 1)
	require.Equal(t, 1, page1.Results[0].value)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page is page 2
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page1.NextCursor, Descending: false}}
	page2, err := Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Len(t, page2.Results, 1)
	require.Equal(t, 2, page2.Results[0].value)

	// Prev page is page 1
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err := Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Len(t, result.Results, 1)
	require.Equal(t, 1, result.Results[0].value)
	require.Equal(t, page1, result)

	// Next page is page 3
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.NextCursor}}
	page3, err := Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Len(t, page3.Results, 1)
	require.Equal(t, 3, page3.Results[0].value)
	require.Empty(t, page3.NextCursor) //  No more pages

	// Prev page is page 2
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page3.PrevCursor, Descending: true}}
	result, err = Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Equal(t, page2, result)

	// First page is page 1
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: "", Descending: false}}
	result, err = Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Equal(t, page1, result)

	// Last page is page 3
	opts.Pagination = &ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: "", Descending: true}}
	result, err = Fetch(ctx, sort, opts, &filter, testFetch)
	require.NoError(t, err)
	require.Equal(t, page3, result)
}

func testFetch(filter *testFilter, options *ts.FindOptions) ([]testObject, error) {
	values := []testObject{{value: 1}, {value: 2}, {value: 3}}

	if options.SortBy == "value DESC" {
		// Reverse the order of values
		for i, j := 0, len(values)-1; i < j; i, j = i+1, j-1 {
			values[i], values[j] = values[j], values[i]
		}
	}

	for _, f := range filter.cursor {
		if intValue, ok := f.Value.(int); ok {
			switch f.Expression {
			case "value > ?":
				values = transforms.Filter(values, func(x testObject) bool { return x.value > intValue })
			case "value < ?":
				values = transforms.Filter(values, func(x testObject) bool { return x.value < intValue })
			}
		}
	}

	if options.Pagination.Limit > 0 && len(values) > int(options.Pagination.Limit) {
		values = values[:options.Pagination.Limit]
	}

	return values, nil
}
