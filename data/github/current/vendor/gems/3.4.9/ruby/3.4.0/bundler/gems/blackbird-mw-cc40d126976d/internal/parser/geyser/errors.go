package geyser

// QueryParserError generic error for non-recoverable search request parsing cases
type QueryParserError string

func (e QueryParserError) Error() string {
	return string(e)
}

// Retryable determines whether it makes sense to retry this error
func (e QueryParserError) Retryable() bool {
	return false
}

// Reportable determines whether it makes sense to report this error
func (e QueryParserError) Reportable() bool {
	return false
}
