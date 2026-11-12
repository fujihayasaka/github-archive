package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"reflect"
	"strings"
	"time"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

func (c *AltClientFactory) checkError(ctx context.Context, target sweagentd.ClientTarget, resp *gg.Response, err error, message string) error {
	return checkError(ctx, target, resp, err, message)
}

func (c *ClientFactory) checkError(ctx context.Context, target sweagentd.ClientTarget, resp *gg.Response, err error, message string) error {
	return checkError(ctx, target, resp, err, message)
}

func (c *Client) checkError(ctx context.Context, resp *gg.Response, err error, message string) error {
	return checkError(ctx, c.target, resp, err, message)
}

func checkError(ctx context.Context, target sweagentd.ClientTarget, resp *gg.Response, err error, message string) error {
	if err == nil {
		return nil
	}
	var primaryRateLimitErr *gg.RateLimitError
	var secondaryRateLimitErr *gg.AbuseRateLimitError
	switch {
	case errors.As(err, &primaryRateLimitErr):
		rate := ratelimits.ToLimiterRate(primaryRateLimitErr.Rate)
		return limiter.NewTargetRateLimitError(target, message, rate)
	case errors.As(err, &secondaryRateLimitErr):
		return limiter.NewTargetAbuseRateLimitError(target, message, secondaryRateLimitErr.GetRetryAfter())
	default:
		return NewGitHubAPIError(resp, message, err)
	}
}

// NewGitHubAPIError creates a new GitHubAPIError with the provided response, message, and error.
//
//nolint:funcorder // Constructor is placed near usage for readability
func NewGitHubAPIError(resp *gg.Response, msg string, err error) *GitHubAPIError {
	return &GitHubAPIError{resp, msg, goerrors.Errorf("%w", err)}
}

// GitHubAPIError represents an error from the GitHub API.
//
//nolint:revive // The stutter in the name is intentional for clarity when used externally.
type GitHubAPIError struct {
	Response *gg.Response
	Message  string
	Err      error
}

func (e *GitHubAPIError) Error() string {
	if e.Err == nil {
		if e.Message != "" {
			return e.Message
		}
		return "unknown github api error"
	}

	var err error
	var ue *url.Error
	if errors.As(e.Err, &ue) {
		// remove http method and url from the error message
		err = ue.Unwrap()
	} else {
		err = e.Err
	}

	if e.Message != "" {
		return fmt.Sprintf("%s: %v", e.Message, err)
	}

	return err.Error()
}

// RequestID returns the GitHub request ID from the response headers, if available.
func (e *GitHubAPIError) RequestID() string {
	if e.Response != nil {
		return e.Response.Header.Get(headers.GitHubRequestID)
	}
	return ""
}

// StatusCode returns the HTTP status code from the response, or 0 if no response.
func (e *GitHubAPIError) StatusCode() int {
	if e.Response != nil {
		return e.Response.StatusCode
	}
	return 0
}

func (e *GitHubAPIError) Unwrap() error {
	return e.Err
}

func (c *Client) checkGQLError(ctx context.Context, err error, message string) error {
	if message == "" {
		message = "failed to perform GraphQL request"
	}

	gqlErr, ok := asGraphQLErrors(err)
	if !ok {
		return goerrors.Errorf("%s: %w", message, err)
	}

	// Handle rate limit errors
	switch {
	case gqlErr.IsRateLimit():
		reset := time.Now().Add(limiter.DefaultRateLimitErrorResetDuration)
		return limiter.NewTargetRateLimitError(c.target, message, limiter.Rate{Limit: 0, Remaining: 0, Reset: reset, Resource: "graphql"})
	case gqlErr.IsSecondaryRateLimit():
		return limiter.NewTargetAbuseRateLimitError(c.target, message, limiter.DefaultAbuseRateLimitResetDuration)
	}

	return goerrors.Errorf("%s: %w", message, gqlErr)
}

// GQLPrimaryRateLimitExceededQuery is a substring of the error message returned
// by GitHub's GraphQL API when the primary rate limit is exceeded. This is used
// to identify rate limit errors in the absence of structured error types.
const GQLPrimaryRateLimitExceededQuery = "API rate limit exceeded"

// GQLPrimaryRateLimitExceededQueryAlt is an alternate substring of the error
// message returned by GitHub's GraphQL API when the primary rate limit is
// exceeded. This is used to identify rate limit errors in the absence of
// structured error types.
const GQLPrimaryRateLimitExceededQueryAlt = "API rate limit already exceeded"

// GQLSecondaryRateLimitExceededQuery is a substring of the error message
// returned by GitHub's GraphQL API when the secondary rate limit is exceeded.
// This is used to identify rate limit errors in the absence of structured error
// types.
const GQLSecondaryRateLimitExceededQuery = "You have exceeded a secondary rate limit"

// GraphQLError represents a structured error returned from a GraphQL API.
//
// Note: The githubv4 package does not expose GraphQL errors directly, so we
// define our own structure here and parse errors as needed.
type GraphQLError struct {
	// HTTP status code from the response. This will not be set if the error
	// if IsQueryError is true.
	Code int

	// Message is a human-readable message describing the error. If the error
	// is a query error, this will be the message from the first error in the
	// list.
	//
	// If the error is not a query error, this will be the top-level message
	// from the GraphQL API, or the entire error string if we could not parse
	// it.
	Message string

	// DocumentationURL is a URL to the documentation for the error, if
	// provided by the API. This will not be set if the error is a query error.
	DocumentationURL string

	// QueryErrors is a list of individual errors returned from the GraphQL
	// query. This will be non-empty if IsQueryError is true.
	//
	// Note: The githubv4 package does not expose GraphQL errors directly, so
	// we define our own structure here and parse errors as needed.
	QueryErrors []QueryError

	// IsQueryError indicates whether this error is from a GraphQL query
	// (i.e., the "errors" array in the GraphQL response) or from a top-level
	// API error (e.g., non-200 HTTP status code).
	IsQueryError bool

	// Err is the original error that was parsed into this GraphQLError.
	Err error
}

// Unwrap allows access to the underlying error.
func (e *GraphQLError) Unwrap() error {
	return e.Err
}

// Error implements the error interface for GraphQLError.
func (e *GraphQLError) Error() string {
	if e.IsQueryError {
		if len(e.QueryErrors) > 0 {
			return e.QueryErrors[0].Error()
		}
		return "GraphQL Query Error: (no details)"
	}
	return fmt.Sprintf("GraphQL API Error: Code=%d, Message=%s, DocumentationURL=%s", e.Code, e.Message, e.DocumentationURL)
}

// IsRateLimit reports whether the error is a rate limit error.
func (e *GraphQLError) IsRateLimit() bool {
	if strings.Contains(e.Message, GQLPrimaryRateLimitExceededQuery) || strings.Contains(e.Message, GQLPrimaryRateLimitExceededQueryAlt) {
		return true
	}
	for _, qe := range e.QueryErrors {
		if strings.Contains(qe.Message, GQLPrimaryRateLimitExceededQuery) || strings.Contains(qe.Message, GQLPrimaryRateLimitExceededQueryAlt) {
			return true
		}
	}
	return false
}

// IsSecondaryRateLimit reports whether this error is a secondary rate limit error.
func (e *GraphQLError) IsSecondaryRateLimit() bool {
	if strings.Contains(e.Message, GQLSecondaryRateLimitExceededQuery) {
		return true
	}
	for _, qe := range e.QueryErrors {
		if strings.Contains(qe.Message, GQLSecondaryRateLimitExceededQuery) {
			return true
		}
	}
	return false
}

// QueryError represents a single error returned from a GraphQL query.
// This is a single error within the "errors" array in a GraphQL response.
type QueryError struct {
	Message   string
	Locations []QueryErrorLocation
}

// QueryErrorLocation represents the location of an error in a GraphQL query.
type QueryErrorLocation struct {
	Line   int
	Column int
}

// Error implements the error interface for QueryError.
func (e *QueryError) Error() string {
	if len(e.Locations) > 0 {
		locs := make([]string, len(e.Locations))
		for i, loc := range e.Locations {
			locs[i] = fmt.Sprintf("Line %d, Column %d", loc.Line, loc.Column)
		}
		return fmt.Sprintf("GraphQL Query Error: %s at %s", e.Message, strings.Join(locs, "; "))
	}
	return fmt.Sprintf("GraphQL Query Error: %s", e.Message)
}

// asGraphQLErrors attempts to parse an error returned from a GraphQL request
// into a structured GraphQLError. It handles errors from both the githubv4
// package and string-based errors returned by the graphql package.
func asGraphQLErrors(err error) (*GraphQLError, bool) {
	gqlErr, ok := asGraphQLStringError(err)
	if ok {
		return gqlErr, true
	}

	gqlErr, ok = asGraphQLPackageError(err)
	if ok {
		return gqlErr, true
	}

	return nil, false
}

// asGraphQLPackageError attempts to parse errors returned by the githubv4
// package. The githubv4 package does not expose GraphQL errors directly, so we
// use reflection to inspect the error structure and extract relevant fields.
func asGraphQLPackageError(err error) (*GraphQLError, bool) {
	if err == nil {
		return nil, false
	}

	// Use reflection to check if the error matches the structure of graphql.errors
	errType := reflect.TypeOf(err)

	// Check if it's a slice type
	if errType.Kind() != reflect.Slice {
		return nil, false
	}

	// Check if the element type is a struct
	elemType := errType.Elem()

	// If it's a pointer, dereference it
	if elemType.Kind() == reflect.Pointer {
		elemType = elemType.Elem()
	}

	if elemType.Kind() != reflect.Struct {
		return nil, false
	}

	// Check if the struct has the expected fields
	if elemType.NumField() < 2 {
		return nil, false
	}

	// Check for "Message" field of type string
	messageField, hasMessage := elemType.FieldByName("Message")
	if !hasMessage || messageField.Type.Kind() != reflect.String {
		return nil, false
	}

	// Check for "Locations" field of type slice
	locationsField, hasLocations := elemType.FieldByName("Locations")
	if !hasLocations || locationsField.Type.Kind() != reflect.Slice {
		return nil, false
	}

	// If all checks pass, convert to our QueryError type
	errValue := reflect.ValueOf(err)
	queryErrs := make([]QueryError, 0, errValue.Len())

	for _, elem := range errValue.Seq2() {
		queryErr := QueryError{}

		if elem.Kind() == reflect.Pointer {
			elem = elem.Elem()
		}

		// Extract Message
		msgField := elem.FieldByName("Message")
		if msgField.IsValid() && msgField.Kind() == reflect.String {
			queryErr.Message = msgField.String()
		}

		// Extract Locations
		locsField := elem.FieldByName("Locations")
		if locsField.IsValid() && locsField.Kind() == reflect.Slice {
			for _, loc := range locsField.Seq2() {
				location := QueryErrorLocation{}

				lineField := loc.FieldByName("Line")
				colField := loc.FieldByName("Column")

				if lineField.IsValid() && lineField.Kind() == reflect.Int {
					location.Line = int(lineField.Int())
				}
				if colField.IsValid() && colField.Kind() == reflect.Int {
					location.Column = int(colField.Int())
				}
				if location.Line == 0 && location.Column == 0 {
					continue
				}
				queryErr.Locations = append(queryErr.Locations, location)
			}
		}
		queryErrs = append(queryErrs, queryErr)
	}

	if len(queryErrs) == 0 {
		return nil, false
	}

	gqlErr := &GraphQLError{
		IsQueryError: true,
		Message:      queryErrs[0].Message,
		QueryErrors:  queryErrs,
		Err:          err,
	}

	return gqlErr, true
}

// parseGraphQLError inspects a GraphQL error and extracts useful information.
// Examples:
//   - "non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"API rate limit exceeded for 108.227.23.60. (But here's the good news: Authenticated requests get a higher rate limit. Check out the documentation for more details.)\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting\\\"}\\n\""
//   - "non-200 OK status code: 403 Forbidden body: \"{\\n  \\\"documentation_url\\\": \\\"https://docs.github.com/free-pro-team@latest/rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits\\\",\\n  \\\"message\\\": \\\"You have exceeded a secondary rate limit. Please wait a few minutes before you try again. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) If you reach out to GitHub Support for help, please include the request ID D3B2:F050:6CEC5:1DDE15:68E6C2E2.\\\"\\n}\""
func asGraphQLStringError(err error) (*GraphQLError, bool) {
	if err == nil {
		return nil, false
	}
	errStr := err.Error()

	// The graphql package wraps errors in a way that makes it hard to extract
	// structured data, but if the error is from the GitHub, and is a non-200
	// response, it is always formatted as "non-200 OK status code: %v body: %q"
	// https://github.com/shurcooL/graphql/blob/ed46e5a4646634fc16cb07c3b8db389542cc8847/graphql.go#L79
	if !strings.HasPrefix(errStr, "non-200 OK status code:") {
		return nil, false
	}

	// Extract status code (e.g., "403" from "403 Forbidden")
	parts := strings.Split(errStr, "status code: ")
	if len(parts) <= 1 {
		return nil, false
	}

	gqlErr := &GraphQLError{
		Message:      errStr,
		IsQueryError: false,
		Err:          err,
	}

	statusPart := strings.TrimSpace(parts[1])
	// Get the numeric code before the status text
	statusParts := strings.Split(statusPart, " ")
	if len(statusParts) > 0 {
		var code int
		_, _ = fmt.Sscanf(statusParts[0], "%d", &code)
		gqlErr.Code = code
	}

	// Extract JSON body
	if !strings.Contains(errStr, "body: \"") {
		return gqlErr, true
	}

	// Find the start of the JSON body
	bodyStart := strings.Index(errStr, "body: \"")
	if bodyStart == -1 {
		return gqlErr, true
	}

	bodyStart += len("body: \"")
	bodyEnd := strings.LastIndex(errStr, "\"")
	if bodyEnd <= bodyStart {
		return gqlErr, true
	}

	// Get the body payload substring
	jsonStr := errStr[bodyStart:bodyEnd]
	// Unescape the JSON string
	jsonStr = strings.ReplaceAll(jsonStr, "\\\"", "\"")
	jsonStr = strings.ReplaceAll(jsonStr, "\\n", "\n")

	// Parse the JSON to extract message and documentation_url
	var bodyData struct {
		Message          string `json:"message"`
		DocumentationURL string `json:"documentation_url"`
	}
	err = json.Unmarshal([]byte(jsonStr), &bodyData)
	if err != nil {
		return gqlErr, true
	}
	if bodyData.Message != "" {
		gqlErr.Message = bodyData.Message
	}
	gqlErr.DocumentationURL = bodyData.DocumentationURL

	return gqlErr, true
}
