package tstypes

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func CreatePaginationInfo(limit uint32, page uint32) ts.Pagination {
	if limit == 0 {
		limit = ts.DEFAULT_PAGE_SIZE
	} else if limit > ts.MAX_PAGE_SIZE {
		limit = ts.MAX_PAGE_SIZE
	}
	if page == 0 {
		page = 1
	}
	offset := (page - 1) * limit

	return ts.Pagination{
		Limit:  limit,
		Offset: offset,
	}
}

func CreateCursorPaginationInfo(limit uint32, beforeCursor, afterCursor string) (ts.Pagination, error) {
	pagination := CreatePaginationInfo(limit, 0)

	if err := addCursorsToPagination(&pagination, beforeCursor, afterCursor); err != nil {
		return pagination, err
	}

	return pagination, nil
}

// CreateHybridPaginationInfo creates a pagination struct for when the request can specify both page-based
// and cursor-based pagination.
func CreateHybridPaginationInfo(limit, page uint32, beforeCursor, afterCursor string) (ts.Pagination, error) {
	pagination := CreatePaginationInfo(limit, page)

	if err := addCursorsToPagination(&pagination, beforeCursor, afterCursor); err != nil {
		return pagination, err
	}

	return pagination, nil
}

func addCursorsToPagination(pagination *ts.Pagination, beforeCursor, afterCursor string) error {
	if beforeCursor != "" && afterCursor != "" {
		return twerrors.InvalidArgumentError("cursor", "before_cursor and after_cursor cannot be used together")
	}

	if beforeCursor != "" {
		pagination.Cursor = &ts.SerializedCursor{
			String:     beforeCursor,
			Descending: true,
		}
	}
	if afterCursor != "" {
		pagination.Cursor = &ts.SerializedCursor{
			String:     afterCursor,
			Descending: false,
		}
	}

	return nil
}
