package mysql

import (
	"fmt"
	"math"
	"sort"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

const defaultCursorPerPage = int32(30)

// PageCursor is an interface for a cursor that can be used to paginate attestations
// DescCursor and AscCursor implement this interface
type PageCursor interface {
	GetAfter() uint64
	GetBefore() uint64
	GetFetchDirection() string
	GetPerPage() int32
	GetQueryLimit() int32
	IsBefore() bool
	SliceAttestations(attestations []attestation.Record) []attestation.Record
	SortAttestations(attestations []attestation.Record) []attestation.Record
	Validate() error
}

// Cursor is a struct that contains the common fields for Cursor types
type Cursor struct {
	PerPage int32
	// Before takes an attestation ID and fetches the previous page of attestations
	// given the current sort order of attestations
	// For the default DESC ID order (managed by DescCursor)
	// Before fetches IDs that are greater than Before ID)
	// For the ASC ID order (managed by AscCursor)
	// Before fetches IDs that are less than Before ID)
	Before uint64
	// After takes an attestation ID and fetches the next page of attestations
	// given the current sort order of attestations
	// For the default DESC ID order (managed by DescCursor)
	// After fetches IDs that are less than After ID
	// For the ASC ID order (managed by AscCursor)
	// After fetches IDs that are greater than After ID
	After uint64
}

func (c *Cursor) Validate() error {
	if c.PerPage <= 0 {
		c.PerPage = 1
	} else if c.PerPage > 100 {
		c.PerPage = 100
	}

	if c.After > 0 && c.Before > 0 {
		return fmt.Errorf("cannot set both After and Before")
	}

	return nil
}

func (c *Cursor) IsBefore() bool {
	return c.Before > 0
}

func (c *Cursor) GetQueryLimit() int32 {
	if c.PerPage <= 0 {
		return 0
	}
	return c.PerPage + 1
}

func (c *Cursor) GetAfter() uint64 {
	return c.After
}

func (c *Cursor) GetBefore() uint64 {
	return c.Before
}

func (c *Cursor) GetPerPage() int32 {
	return c.PerPage
}

// NewCursorFromRequest creates a new cursor from a request with the default descending sort order
func NewCursor(rpcPerPage uint32, rpcAfter, rpcBefore uint64) (*DescCursor, error) {
	cursor, err := NewCursorWithCustomSort(attestation.SortDirectionDesc, rpcPerPage, rpcAfter, rpcBefore)
	if err != nil {
		return nil, err
	}
	// cast the returned cursor to the default Cursor type to confirm the sort direction is correct
	return cursor.(*DescCursor), nil
}

func NewCursorWithCustomSort(direction attestation.SortDirection, rpcPerPage uint32, rpcAfter, rpcBefore uint64) (PageCursor, error) {
	if rpcPerPage > math.MaxInt32 {
		return nil, fmt.Errorf("invalid PerPage value: %d", rpcPerPage)
	}

	// nolint:gosec // we ensured that this should not overflow
	perPage := int32(rpcPerPage)

	if perPage == 0 {
		perPage = defaultCursorPerPage // default PerPage
	}

	if direction == attestation.SortDirectionAsc {
		cursor := &AscCursor{}
		cursor.PerPage = perPage
		cursor.After = rpcAfter
		cursor.Before = rpcBefore
		if err := cursor.Validate(); err != nil {
			return nil, err
		}
		return cursor, nil
	}

	cursor := &DescCursor{}
	cursor.PerPage = perPage
	cursor.After = rpcAfter
	cursor.Before = rpcBefore
	if err := cursor.Validate(); err != nil {
		return nil, err
	}
	return cursor, nil
}

// DescCursor represents the default pagination cursor,
// which always returns attestations in descending order by ID.
type DescCursor struct {
	Cursor
}

// GetFetchDirection this function returns the order by direction for fetching the next page of attestations
func (c *DescCursor) GetFetchDirection() string {
	if c.IsBefore() {
		return "ASC"
	}
	return "DESC"
}

// SliceAttestations this function slices the attestations based Before or After values
func (c *DescCursor) SliceAttestations(attestations []attestation.Record) []attestation.Record {
	if c.IsBefore() {
		return attestations[1:]
	}
	return attestations[:c.PerPage]
}

// SortAttestations sorts the attestations in descending order
func (c *DescCursor) SortAttestations(attestations []attestation.Record) []attestation.Record {
	sort.Slice(attestations, func(i, j int) bool {
		return attestations[i].ID > attestations[j].ID
	})
	return attestations
}

// calculatePageInfo calculates the page info for the attestations, which depends on
// the sort order and the cursor values
func calculatePageInfo(cursor PageCursor, attestations []attestation.Record) ([]attestation.Record, *attestation.PageInfo, error) {
	// to clean the attestations and return only the requested records with pagination information
	if len(attestations) == 0 {
		return attestations, nil, nil
	}

	// Step 1: check if there are more records than requested
	hasMore := false
	// to set hasMore to true if there are more records than requested
	if cursor.GetPerPage() > 0 && len(attestations) > int(cursor.GetPerPage()) {
		hasMore = true
		// Step 2: slice the records with requested page size
		// We need to slice out the first or last record as we fetched perPage + 1 to
		// compute "hasMore" depending on the QUERY order (returned order is always DESC),
		// when fetching with before (backwards) we query ASC so we slice out the first item,
		// when fetching with after (forwards) we query DESC so we slice out the last item
		attestations = cursor.SliceAttestations(attestations)
	}

	// Step 3: construct the page info
	pageInfo := &attestation.PageInfo{}

	// if there are more records than requested, set hasMore to true based on the query order
	if hasMore {
		if cursor.IsBefore() {
			pageInfo.HasPreviousPage = true
		} else {
			pageInfo.HasNextPage = true
		}
	}

	attestations = cursor.SortAttestations(attestations)

	// set the start and end cursor positions
	if len(attestations) > 0 {
		pageInfo.StartCursor = attestations[0].ID
		pageInfo.EndCursor = attestations[len(attestations)-1].ID
	}
	return attestations, pageInfo, nil
}

// AscCursor always returns attestations in ascending order by ID.
type AscCursor struct {
	Cursor
}

// GetFetchDirection this function returns the order by direction for fetching the next page of attestations
func (c *AscCursor) GetFetchDirection() string {
	if c.IsBefore() {
		return "DESC"
	}
	return "ASC"
}

func (c *AscCursor) GetAfter() uint64 {
	// Return the Before value as the After value because the queries always return records in DESC order.
	// When the query is provided an after cursor value, it will filter for records with
	// an ID less than the After cursor value. The query will filter for records with
	// an ID greater than a provided Before cursor value. So we need to reverse
	// the before and after values to ensure the query is correct.
	after := c.Before
	return after
}

func (c *AscCursor) GetBefore() uint64 {
	// Return the After value as the Before value because the queries always return records in DESC order.
	// When the query is provided an after cursor value, it will filter for records with
	// an ID less than the After cursor value. The query will filter for records with
	// an ID greater than a provided Before cursor value. So we need to reverse
	// the before and after values to ensure the query is correct.
	before := c.After
	return before
}

// SliceAttestations slices the attestations based Before or After values
func (c *AscCursor) SliceAttestations(attestations []attestation.Record) []attestation.Record {
	if c.IsBefore() {
		return attestations[:c.PerPage]
	}
	return attestations[1:]
}

// SortAttestations sorts the attestations in ascending order
func (c *AscCursor) SortAttestations(attestations []attestation.Record) []attestation.Record {
	sort.Slice(attestations, func(i, j int) bool {
		return attestations[i].ID < attestations[j].ID
	})
	return attestations
}
