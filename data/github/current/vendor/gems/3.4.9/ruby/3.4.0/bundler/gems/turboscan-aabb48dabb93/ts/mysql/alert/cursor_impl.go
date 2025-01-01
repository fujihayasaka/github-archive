package alert

import (
	"context"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
)

// SearchResult represents the result of a fetch operation
type SearchResult[T any] struct {
	Results    []T
	PrevCursor string
	NextCursor string
}

// Fetch is a generic fetch method for fetching results from a database taking cursor manipulation into account.
func Fetch[F ts.SQLCursorSupported, T any](ctx context.Context, sort ts.CursorSort[T], baseOptions *ts.FindOptions, baseFilter F, fetchResults func(filter F, options *ts.FindOptions) ([]T, error)) (SearchResult[T], error) {

	result := SearchResult[T]{Results: []T{}}

	pagination := baseOptions.Pagination

	// If there is a decending cursor then we need to reverse the sort
	if pagination.Cursor != nil && pagination.Cursor.Descending {
		sort.Descending = !sort.Descending
	}

	// We need to fetch an additional element to know whether there are more results.
	paginationCopy := *pagination
	paginationCopy.Limit += 1

	// If there is an active cursor we need to filter based on it
	if pagination.Cursor != nil {
		decodedCursor, err := ts.DecodeCursor(pagination.Cursor.String)
		if err != nil {
			// Cursor is invalid, return empty result
			appctx.Stats(ctx).Counter("alerts.invalid_query.count", stats.Tags{"reason": "cursor"}, 1)
			return result, nil
		}

		cursorFilter, err := sort.FilterBy(decodedCursor)
		if err != nil {
			// Cursor is invalid, return empty result
			appctx.Stats(ctx).Counter("alerts.invalid_query.count", stats.Tags{"reason": "cursor_filter"}, 1)
			return result, nil
		}
		baseFilter.SetCursorFilter(cursorFilter)
	}

	options := *baseOptions
	options.SortBy = sort.OrderBy()
	options.Pagination = &paginationCopy

	results, err := fetchResults(baseFilter, &options)
	if err != nil {
		return result, err
	}
	if len(results) == 0 {
		return result, nil
	}

	hasPrev := pagination.Offset > 0 || (pagination.Cursor != nil && pagination.Cursor.String != "")
	hasNext := len(results) == int(paginationCopy.Limit) // This means we fetched the original limit + 1

	if hasNext {
		// We fetched one extra element (in the back) and need to remove it
		results = results[:len(results)-1]
	}

	// If the results were fetched reversed, flip them back to the correct order
	if pagination.Cursor != nil && pagination.Cursor.Descending {
		for i, j := 0, len(results)-1; i < j; i, j = i+1, j-1 {
			results[i], results[j] = results[j], results[i]
		}
		// For descending cursors the meaning of previous and next is swapped.
		hasPrev, hasNext = hasNext, hasPrev
	}

	result.Results = results

	if hasPrev {
		first := results[0]
		prev := sort.BuildCursor(first)
		encodedPrevCursor, err := ts.EncodeCursor(prev)
		if err != nil {
			// Don't break the search if we can't build a cursor
			appctx.Logger(ctx).WithError(err).Error("failed to encode prev cursor")
		}
		result.PrevCursor = encodedPrevCursor
	}

	if hasNext {
		last := results[len(results)-1]
		next := sort.BuildCursor(last)
		encodedNextCursor, err := ts.EncodeCursor(next)
		if err != nil {
			// Don't break the search if we can't build a cursor
			appctx.Logger(ctx).WithError(err).Error("failed to encode next cursor")
		}
		result.NextCursor = encodedNextCursor
	}

	return result, nil
}
