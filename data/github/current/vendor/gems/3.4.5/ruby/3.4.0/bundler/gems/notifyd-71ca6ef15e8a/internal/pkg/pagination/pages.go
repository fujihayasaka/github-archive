package pagination

// Pages is the interface for a page of results.
type Pages interface {
	NextCursor() string
	ReturnNextCursor() bool
}

// StandardPages represents pages of results.
type StandardPages struct {
	nextEncodedCursor string
}

// NextCursor returns the next cursor.
func (p StandardPages) NextCursor() string {
	return p.nextEncodedCursor
}

// ReturnNextCursor returns true if the next cursor can be returned.
func (p StandardPages) ReturnNextCursor() bool {
	return true
}

// NewStandardPages creates a new StandardPages.
func NewStandardPages(cursor string) StandardPages {
	return StandardPages{
		nextEncodedCursor: cursor,
	}
}

// EmptyStandardPages represents an empty pages of results.
type EmptyStandardPages struct {
}

// NextCursor returns the next cursor.
func (p EmptyStandardPages) NextCursor() string {
	return ""
}

// ReturnNextCursor returns true if the next cursor can be returned.
func (p EmptyStandardPages) ReturnNextCursor() bool {
	return false
}

// NewEmptyStandardPages creates a new EmptyStandardPages.
func NewEmptyStandardPages() EmptyStandardPages {
	return EmptyStandardPages{}
}
