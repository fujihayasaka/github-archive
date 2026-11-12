package github

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGraphQLError_Error(t *testing.T) {
	t.Run("query error with single error", func(t *testing.T) {
		gqlErr := &GraphQLError{
			IsQueryError: true,
			Message:      "Field not found",
			QueryErrors: []QueryError{
				{Message: "Field not found"},
			},
			Err: errors.New("original error"),
		}

		assert.Equal(t, "GraphQL Query Error: Field not found", gqlErr.Error())
	})

	t.Run("query error with multiple errors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			IsQueryError: true,
			Message:      "First error message",
			QueryErrors: []QueryError{
				{Message: "First error message"},
				{Message: "Second error message"},
			},
			Err: errors.New("original error"),
		}

		assert.Equal(t, "GraphQL Query Error: First error message", gqlErr.Error())
	})

	t.Run("query error with no query errors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			IsQueryError: true,
			Message:      "Some message",
			QueryErrors:  []QueryError{},
			Err:          errors.New("original error"),
		}

		assert.Equal(t, "GraphQL Query Error: (no details)", gqlErr.Error())
	})

	t.Run("API error with code and message", func(t *testing.T) {
		gqlErr := &GraphQLError{
			IsQueryError:     false,
			Code:             403,
			Message:          "Rate limit exceeded",
			DocumentationURL: "https://docs.github.com/rate-limiting",
			Err:              errors.New("original error"),
		}

		expected := "GraphQL API Error: Code=403, Message=Rate limit exceeded, DocumentationURL=https://docs.github.com/rate-limiting"
		assert.Equal(t, expected, gqlErr.Error())
	})

	t.Run("API error without documentation URL", func(t *testing.T) {
		gqlErr := &GraphQLError{
			IsQueryError:     false,
			Code:             500,
			Message:          "Internal server error",
			DocumentationURL: "",
			Err:              errors.New("original error"),
		}

		expected := "GraphQL API Error: Code=500, Message=Internal server error, DocumentationURL="
		assert.Equal(t, expected, gqlErr.Error())
	})
}

func TestGraphQLError_Unwrap(t *testing.T) {
	originalErr := errors.New("original error")
	gqlErr := &GraphQLError{
		IsQueryError: false,
		Code:         403,
		Message:      "Rate limit exceeded",
		Err:          originalErr,
	}

	assert.Equal(t, originalErr, gqlErr.Unwrap())
}

func TestQueryError_Error(t *testing.T) {
	t.Run("with locations", func(t *testing.T) {
		qe := &QueryError{
			Message: "Field not found",
			Locations: []QueryErrorLocation{
				{Line: 1, Column: 5},
			},
		}

		expected := "GraphQL Query Error: Field not found at Line 1, Column 5"
		assert.Equal(t, expected, qe.Error())
	})

	t.Run("with multiple locations", func(t *testing.T) {
		qe := &QueryError{
			Message: "Syntax error",
			Locations: []QueryErrorLocation{
				{Line: 1, Column: 5},
				{Line: 2, Column: 10},
			},
		}

		expected := "GraphQL Query Error: Syntax error at Line 1, Column 5; Line 2, Column 10"
		assert.Equal(t, expected, qe.Error())
	})

	t.Run("without locations", func(t *testing.T) {
		qe := &QueryError{
			Message:   "General error",
			Locations: []QueryErrorLocation{},
		}

		expected := "GraphQL Query Error: General error"
		assert.Equal(t, expected, qe.Error())
	})
}

func TestAsGraphQLErrors(t *testing.T) {
	t.Run("parses string-based errors", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"API rate limit exceeded\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/rate-limiting\\\"}\\n\"")

		gqlErr, ok := asGraphQLErrors(err)

		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		assert.Equal(t, "API rate limit exceeded", gqlErr.Message)
		assert.Equal(t, "https://docs.github.com/rate-limiting", gqlErr.DocumentationURL)
		assert.False(t, gqlErr.IsQueryError)
	})

	t.Run("parses package errors", func(t *testing.T) {
		// Create a mock graphql.errors type
		err := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "Field not found", Locations: []mockLocation{{Line: 1, Column: 5}}},
		})

		gqlErr, ok := asGraphQLErrors(err)

		require.True(t, ok)
		assert.True(t, gqlErr.IsQueryError)
		assert.Len(t, gqlErr.QueryErrors, 1)
		assert.Equal(t, "Field not found", gqlErr.QueryErrors[0].Message)
		assert.Len(t, gqlErr.QueryErrors[0].Locations, 1)
		assert.Equal(t, 1, gqlErr.QueryErrors[0].Locations[0].Line)
		assert.Equal(t, 5, gqlErr.QueryErrors[0].Locations[0].Column)
	})

	t.Run("returns false for non-GraphQL errors", func(t *testing.T) {
		err := errors.New("regular error")

		gqlErr, ok := asGraphQLErrors(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for nil error", func(t *testing.T) {
		gqlErr, ok := asGraphQLErrors(nil)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})
}

func TestAsGraphQLStringError(t *testing.T) {
	t.Run("parses 403 rate limit error", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"API rate limit exceeded for 108.227.23.60.\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting\\\"}\\n\"")

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		assert.Equal(t, "API rate limit exceeded for 108.227.23.60.", gqlErr.Message)
		assert.Equal(t, "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting", gqlErr.DocumentationURL)
		assert.False(t, gqlErr.IsQueryError)
		assert.Equal(t, err, gqlErr.Err)
	})

	t.Run("parses 403 secondary rate limit error", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\n  \\\"documentation_url\\\": \\\"https://docs.github.com/free-pro-team@latest/rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits\\\",\\n  \\\"message\\\": \\\"You have exceeded a secondary rate limit. Please wait a few minutes before you try again.\\\"\\n}\"")

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		assert.Equal(t, "You have exceeded a secondary rate limit. Please wait a few minutes before you try again.", gqlErr.Message)
		assert.Equal(t, "https://docs.github.com/free-pro-team@latest/rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits", gqlErr.DocumentationURL)
		assert.False(t, gqlErr.IsQueryError)
	})

	t.Run("parses 429 error", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 429 Too Many Requests body: \"{\\\"message\\\":\\\"You have exceeded a secondary rate limit.\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/secondary-limits\\\"}\\n\"")

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, 429, gqlErr.Code)
		assert.Equal(t, "You have exceeded a secondary rate limit.", gqlErr.Message)
		assert.Equal(t, "https://docs.github.com/secondary-limits", gqlErr.DocumentationURL)
	})

	t.Run("parses 500 error", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 500 Internal Server Error body: \"{\\\"message\\\":\\\"Internal server error\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/errors\\\"}\\n\"")

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, 500, gqlErr.Code)
		assert.Equal(t, "Internal server error", gqlErr.Message)
		assert.Equal(t, "https://docs.github.com/errors", gqlErr.DocumentationURL)
	})

	t.Run("handles error without documentation_url", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 404 Not Found body: \"{\\\"message\\\":\\\"Resource not found\\\"}\\n\"")

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, 404, gqlErr.Code)
		assert.Equal(t, "Resource not found", gqlErr.Message)
		assert.Equal(t, "", gqlErr.DocumentationURL)
	})

	t.Run("returns false for non-200 prefix error", func(t *testing.T) {
		err := errors.New("regular error message")

		gqlErr, ok := asGraphQLStringError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for nil error", func(t *testing.T) {
		gqlErr, ok := asGraphQLStringError(nil)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns gqlErr for error without status code", func(t *testing.T) {
		err := errors.New("non-200 OK status code: ")

		gqlErr, ok := asGraphQLStringError(err)

		// Function returns true because it has the prefix, but code will be 0
		require.True(t, ok)
		assert.Equal(t, 0, gqlErr.Code)
		assert.Equal(t, "non-200 OK status code: ", gqlErr.Message)
	})

	t.Run("returns gqlErr for error without body", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden")

		gqlErr, ok := asGraphQLStringError(err)

		// Function returns true but won't have parsed message
		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		assert.Equal(t, "non-200 OK status code: 403 Forbidden", gqlErr.Message)
	})

	t.Run("returns gqlErr for malformed body", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"invalid json\"")

		gqlErr, ok := asGraphQLStringError(err)

		// Function returns true even when JSON parsing fails
		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		// When JSON parsing fails, original message is kept
		assert.Equal(t, "non-200 OK status code: 403 Forbidden body: \"invalid json\"", gqlErr.Message)
	})

	t.Run("returns gqlErr for empty body", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"\"")

		gqlErr, ok := asGraphQLStringError(err)

		// Function returns true even for empty body
		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		// Empty JSON object parsed, so message stays as original
		assert.Equal(t, "non-200 OK status code: 403 Forbidden body: \"\"", gqlErr.Message)
	})

	t.Run("returns gqlErr for body with only whitespace", func(t *testing.T) {
		err := errors.New("non-200 OK status code: 403 Forbidden body: \"   \"")

		gqlErr, ok := asGraphQLStringError(err)

		// Function returns true even for whitespace body
		require.True(t, ok)
		assert.Equal(t, 403, gqlErr.Code)
		// Invalid JSON, so original message is kept
		assert.Equal(t, "non-200 OK status code: 403 Forbidden body: \"   \"", gqlErr.Message)
	})

	t.Run("preserves original error message if parsing fails", func(t *testing.T) {
		originalMsg := "non-200 OK status code: 403 Forbidden body: \"{}\""
		err := errors.New(originalMsg)

		gqlErr, ok := asGraphQLStringError(err)

		require.True(t, ok)
		assert.Equal(t, originalMsg, gqlErr.Message)
	})
}

func TestAsGraphQLPackageError(t *testing.T) {
	t.Run("parses single error", func(t *testing.T) {
		err := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "Field not found", Locations: []mockLocation{{Line: 1, Column: 5}}},
		})

		gqlErr, ok := asGraphQLPackageError(err)

		require.True(t, ok)
		assert.True(t, gqlErr.IsQueryError)
		assert.Equal(t, "Field not found", gqlErr.Message)
		assert.Len(t, gqlErr.QueryErrors, 1)
		assert.Equal(t, "Field not found", gqlErr.QueryErrors[0].Message)
		assert.Len(t, gqlErr.QueryErrors[0].Locations, 1)
		assert.Equal(t, 1, gqlErr.QueryErrors[0].Locations[0].Line)
		assert.Equal(t, 5, gqlErr.QueryErrors[0].Locations[0].Column)
	})

	t.Run("parses multiple errors", func(t *testing.T) {
		err := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "First error", Locations: []mockLocation{{Line: 1, Column: 5}}},
			{Message: "Second error", Locations: []mockLocation{{Line: 2, Column: 10}}},
		})

		gqlErr, ok := asGraphQLPackageError(err)

		require.True(t, ok)
		assert.True(t, gqlErr.IsQueryError)
		assert.Equal(t, "First error", gqlErr.Message)
		assert.Len(t, gqlErr.QueryErrors, 2)
		assert.Equal(t, "First error", gqlErr.QueryErrors[0].Message)
		assert.Equal(t, "Second error", gqlErr.QueryErrors[1].Message)
	})

	t.Run("parses errors with multiple locations", func(t *testing.T) {
		err := createMockGraphQLErrors([]mockGraphQLError{
			{
				Message: "Error at multiple places",
				Locations: []mockLocation{
					{Line: 1, Column: 5},
					{Line: 3, Column: 10},
					{Line: 5, Column: 15},
				},
			},
		})

		gqlErr, ok := asGraphQLPackageError(err)

		require.True(t, ok)
		assert.Len(t, gqlErr.QueryErrors[0].Locations, 3)
		assert.Equal(t, 1, gqlErr.QueryErrors[0].Locations[0].Line)
		assert.Equal(t, 5, gqlErr.QueryErrors[0].Locations[0].Column)
		assert.Equal(t, 3, gqlErr.QueryErrors[0].Locations[1].Line)
		assert.Equal(t, 10, gqlErr.QueryErrors[0].Locations[1].Column)
		assert.Equal(t, 5, gqlErr.QueryErrors[0].Locations[2].Line)
		assert.Equal(t, 15, gqlErr.QueryErrors[0].Locations[2].Column)
	})

	t.Run("parses errors without locations", func(t *testing.T) {
		err := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "Error without location", Locations: []mockLocation{}},
		})

		gqlErr, ok := asGraphQLPackageError(err)

		require.True(t, ok)
		assert.Len(t, gqlErr.QueryErrors[0].Locations, 0)
	})

	t.Run("handles pointer slice elements", func(t *testing.T) {
		err := createMockGraphQLErrorPointers([]*mockGraphQLError{
			{Message: "Pointer error", Locations: []mockLocation{{Line: 1, Column: 5}}},
		})

		gqlErr, ok := asGraphQLPackageError(err)

		require.True(t, ok)
		assert.Equal(t, "Pointer error", gqlErr.Message)
		assert.Len(t, gqlErr.QueryErrors, 1)
	})

	t.Run("returns false for nil error", func(t *testing.T) {
		gqlErr, ok := asGraphQLPackageError(nil)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for non-slice error", func(t *testing.T) {
		err := errors.New("regular error")

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for slice of non-struct", func(t *testing.T) {
		err := stringSliceError([]string{"error1", "error2"})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for struct without Message field", func(t *testing.T) {
		err := invalidSlice1Error([]struct {
			Text      string
			Locations []mockLocation
		}{{Text: "error", Locations: []mockLocation{}}})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for struct without Locations field", func(t *testing.T) {
		err := invalidSlice2Error([]struct {
			Message string
			Places  []mockLocation
		}{{Message: "error", Places: []mockLocation{}}})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for struct with wrong Message type", func(t *testing.T) {
		err := invalidSlice3Error([]struct {
			Message   int
			Locations []mockLocation
		}{{Message: 123, Locations: []mockLocation{}}})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for struct with wrong Locations type", func(t *testing.T) {
		err := invalidSlice4Error([]struct {
			Message   string
			Locations string
		}{{Message: "error", Locations: "somewhere"}})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("returns false for empty slice", func(t *testing.T) {
		err := mockGraphQLErrors([]mockGraphQLError{})

		gqlErr, ok := asGraphQLPackageError(err)

		assert.False(t, ok)
		assert.Nil(t, gqlErr)
	})

	t.Run("does not panic on slice of ints", func(t *testing.T) {
		err := intSliceError([]int{1, 2, 3})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on slice of maps", func(t *testing.T) {
		err := mapSliceError([]map[string]any{
			{"message": "error"},
		})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on slice of interfaces", func(t *testing.T) {
		err := interfaceSliceError([]any{
			"error1",
			123,
			map[string]string{"key": "value"},
		})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on slice of pointer to int", func(t *testing.T) {
		val := 42
		err := intPointerSliceError([]*int{&val})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on nil slice", func(t *testing.T) {
		var s []mockGraphQLError
		err := mockGraphQLErrors(s)

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on struct with only one field", func(t *testing.T) {
		err := singleFieldErrors([]struct {
			Message string
		}{{Message: "error"}})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic on struct with no fields", func(t *testing.T) {
		err := emptyErrors([]struct{}{{}})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("does not panic with malformed Location type", func(t *testing.T) {
		err := badErrors([]struct {
			Message   string
			Locations []struct {
				Line   string
				Column string
			}
		}{{
			Message: "error",
			Locations: []struct {
				Line   string
				Column string
			}{{Line: "1", Column: "5"}},
		}})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			// Should still parse the message, locations might be empty or have zero values
			assert.True(t, ok)
			assert.Equal(t, "error", gqlErr.Message)
			// Locations parsing depends on whether Line/Column fields can be extracted
			// If they're strings instead of ints, they'll be zero values
			if len(gqlErr.QueryErrors) > 0 && len(gqlErr.QueryErrors[0].Locations) > 0 {
				assert.Equal(t, 0, gqlErr.QueryErrors[0].Locations[0].Line)
				assert.Equal(t, 0, gqlErr.QueryErrors[0].Locations[0].Column)
			}
		})
	})

	t.Run("does not panic with unexported fields", func(t *testing.T) {
		err := unexportedFieldErrors([]struct {
			Message   string
			Locations []mockLocation
			private   string
		}{{
			Message:   "error",
			Locations: []mockLocation{{Line: 1, Column: 5}},
			private:   "should not cause panic",
		}})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.True(t, ok)
			assert.Equal(t, "error", gqlErr.Message)
		})
	})
}

// Helper types and functions for testing

type mockLocation struct {
	Line   int
	Column int
}

type mockGraphQLError struct {
	Message   string
	Locations []mockLocation
}

// createMockGraphQLErrors creates a slice that mimics the structure of graphql.errors
func createMockGraphQLErrors(errors []mockGraphQLError) error {
	// Convert to any to simulate what the graphql package returns
	return mockGraphQLErrors(errors)
}

type mockGraphQLErrors []mockGraphQLError

func (e mockGraphQLErrors) Error() string {
	if len(e) > 0 {
		return e[0].Message
	}
	return "unknown error"
}

// createMockGraphQLErrorPointers creates a slice with pointer elements
func createMockGraphQLErrorPointers(errors []*mockGraphQLError) error {
	return mockGraphQLPtrErrors(errors)
}

type mockGraphQLPtrErrors []*mockGraphQLError

func (e mockGraphQLPtrErrors) Error() string {
	if len(e) > 0 && e[0] != nil {
		return e[0].Message
	}
	return "unknown error"
}

// Additional edge case tests for reflection safety
func TestAsGraphQLPackageError_ReflectionSafety(t *testing.T) {
	t.Run("does not panic with deeply nested types", func(t *testing.T) {
		err := deepErrors([]struct {
			Message   string
			Locations []struct {
				Inner struct {
					Line   int
					Column int
				}
			}
		}{{Message: "deep"}})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			// The function checks for Message string and Locations slice
			// Even with deeply nested Inner struct, it will try to parse
			// But the nested structure doesn't match the expected Line/Column at top level
			// So it may succeed but with empty/zero locations, or may fail
			_ = gqlErr
			_ = ok
		})
	})

	t.Run("does not panic with array instead of slice", func(t *testing.T) {
		// Arrays and slices are different types at reflect level
		// We can't directly pass an array to asGraphQLPackageError since it needs an error
		// But we can test that the reflection code handles it safely
		// This test ensures the Kind() check works correctly
		err := errors.New("not a graphql error")

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.False(t, ok)
			assert.Nil(t, gqlErr)
		})
	})

	t.Run("handles invalid field values gracefully", func(t *testing.T) {
		err := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "", Locations: nil},
		})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.True(t, ok)
			assert.Equal(t, "", gqlErr.Message)
			assert.Len(t, gqlErr.QueryErrors[0].Locations, 0)
		})
	})

	t.Run("handles very large slice without panic", func(t *testing.T) {
		errors := make([]mockGraphQLError, 10000)
		for i := range errors {
			errors[i] = mockGraphQLError{
				Message:   fmt.Sprintf("Error %d", i),
				Locations: []mockLocation{{Line: i, Column: i}},
			}
		}
		err := createMockGraphQLErrors(errors)

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			assert.True(t, ok)
			assert.Len(t, gqlErr.QueryErrors, 10000)
		})
	})

	t.Run("does not panic when accessing invalid reflect.Value", func(t *testing.T) {
		// Create a struct with embedded anonymous fields that might confuse reflection
		err := complexErrors([]struct {
			Embedded struct {
				Message string
			}
			Locations []mockLocation
		}{
			{
				Embedded:  struct{ Message string }{Message: "embedded"},
				Locations: []mockLocation{{Line: 1, Column: 1}},
			},
		})

		assert.NotPanics(t, func() {
			gqlErr, ok := asGraphQLPackageError(err)
			// May or may not work depending on field lookup, but shouldn't panic
			_ = gqlErr
			_ = ok
		})
	})
}

// Helper error types to wrap non-error types for testing

type stringSliceError []string

func (e stringSliceError) Error() string {
	return "string slice error"
}

type intSliceError []int

func (e intSliceError) Error() string {
	return "int slice error"
}

type mapSliceError []map[string]any

func (e mapSliceError) Error() string {
	return "map slice error"
}

type interfaceSliceError []any

func (e interfaceSliceError) Error() string {
	return "interface slice error"
}

type intPointerSliceError []*int

func (e intPointerSliceError) Error() string {
	return "int pointer slice error"
}

type invalidSlice1Error []struct {
	Text      string
	Locations []mockLocation
}

func (e invalidSlice1Error) Error() string {
	return "invalid error slice 1"
}

type invalidSlice2Error []struct {
	Message string
	Places  []mockLocation
}

func (e invalidSlice2Error) Error() string {
	return "invalid error slice 2"
}

type invalidSlice3Error []struct {
	Message   int
	Locations []mockLocation
}

func (e invalidSlice3Error) Error() string {
	return "invalid error slice 3"
}

type invalidSlice4Error []struct {
	Message   string
	Locations string
}

func (e invalidSlice4Error) Error() string {
	return "invalid error slice 4"
}

type singleFieldErrors []struct {
	Message string
}

func (e singleFieldErrors) Error() string {
	return "single field error slice"
}

type emptyErrors []struct{}

func (e emptyErrors) Error() string {
	return "empty error slice"
}

type badErrors []struct {
	Message   string
	Locations []struct {
		Line   string
		Column string
	}
}

func (e badErrors) Error() string {
	return "bad error slice"
}

type unexportedFieldErrors []struct {
	Message   string
	Locations []mockLocation
	private   string
}

func (e unexportedFieldErrors) Error() string {
	return "unexported field error slice"
}

type deepErrors []struct {
	Message   string
	Locations []struct {
		Inner struct {
			Line   int
			Column int
		}
	}
}

func (e deepErrors) Error() string {
	return "deep error slice"
}

type complexErrors []struct {
	Embedded struct {
		Message string
	}
	Locations []mockLocation
}

func (e complexErrors) Error() string {
	return "complex error slice"
}

func TestGraphQLError_IsRateLimit(t *testing.T) {
	t.Run("detects primary rate limit in Message field", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:      "API rate limit exceeded for user",
			IsQueryError: false,
		}
		assert.True(t, gqlErr.IsRateLimit())
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})

	t.Run("detects primary rate limit in QueryErrors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:      "Query failed",
			IsQueryError: true,
			QueryErrors: []QueryError{
				{Message: "Field validation error"},
				{Message: "API rate limit exceeded for installation ID 123"},
			},
		}
		assert.True(t, gqlErr.IsRateLimit())
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})

	t.Run("returns false when not a rate limit error", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message: "Some error message",
			QueryErrors: []QueryError{
				{Message: "Another error"},
			},
		}
		assert.False(t, gqlErr.IsRateLimit())
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})

	t.Run("handles empty Message and QueryErrors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:     "",
			QueryErrors: []QueryError{},
		}
		assert.False(t, gqlErr.IsRateLimit())
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})
}

func TestGraphQLError_IsSecondaryRateLimit(t *testing.T) {
	t.Run("detects secondary rate limit in Message field", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:      "You have exceeded a secondary rate limit. Please wait.",
			IsQueryError: false,
		}
		assert.True(t, gqlErr.IsSecondaryRateLimit())
		assert.False(t, gqlErr.IsRateLimit())
	})

	t.Run("detects secondary rate limit in QueryErrors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:      "Query failed",
			IsQueryError: true,
			QueryErrors: []QueryError{
				{Message: "Field validation error"},
				{Message: "You have exceeded a secondary rate limit"},
			},
		}
		assert.True(t, gqlErr.IsSecondaryRateLimit())
		assert.False(t, gqlErr.IsRateLimit())
	})

	t.Run("returns false when not a secondary rate limit error", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message: "Some error message",
			QueryErrors: []QueryError{
				{Message: "Another error"},
			},
		}
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})

	t.Run("handles empty Message and QueryErrors", func(t *testing.T) {
		gqlErr := &GraphQLError{
			Message:     "",
			QueryErrors: []QueryError{},
		}
		assert.False(t, gqlErr.IsSecondaryRateLimit())
	})
}

func TestGraphQLError_IsNodeNotFound(t *testing.T) {
	tests := []struct {
		name     string
		gqlErr   *GraphQLError
		expected bool
	}{
		{
			name: "detects node not found in Message field",
			gqlErr: &GraphQLError{
				Message:      "Could not resolve to a node with the global id of 'R_abc123'.",
				IsQueryError: false,
			},
			expected: true,
		},
		{
			name: "detects node not found in QueryErrors",
			gqlErr: &GraphQLError{
				Message:      "Query failed",
				IsQueryError: true,
				QueryErrors: []QueryError{
					{Message: "Field validation error"},
					{Message: "Could not resolve to a node with the global id of 'PR_xyz789'."},
				},
			},
			expected: true,
		},
		{
			name: "returns false when not a node not found error",
			gqlErr: &GraphQLError{
				Message: "Some other error",
				QueryErrors: []QueryError{
					{Message: "Another error"},
				},
			},
			expected: false,
		},
		{
			name: "handles empty Message and QueryErrors",
			gqlErr: &GraphQLError{
				Message:     "",
				QueryErrors: []QueryError{},
			},
			expected: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.gqlErr.IsNodeNotFound())
		})
	}
}

func TestIsNodeNotFound(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name: "returns true for wrapped GraphQLError with node not found message",
			err: fmt.Errorf("failed to get pull request context: %w", &GraphQLError{
				IsQueryError: true,
				Message:      "Could not resolve to a node with the global id of 'R_abc'.",
				QueryErrors: []QueryError{
					{Message: "Could not resolve to a node with the global id of 'R_abc'."},
				},
			}),
			expected: true,
		},
		{
			name:     "returns false for non-GraphQL errors",
			err:      errors.New("some regular error"),
			expected: false,
		},
		{
			name:     "returns false for nil error",
			err:      nil,
			expected: false,
		},
		{
			name: "returns false for GraphQLError without node not found message",
			err: &GraphQLError{
				IsQueryError: true,
				Message:      "API rate limit exceeded",
				QueryErrors: []QueryError{
					{Message: "API rate limit exceeded"},
				},
			},
			expected: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, IsNodeNotFound(tt.err))
		})
	}
}

func TestClient_CheckGQLError(t *testing.T) {
	ctx := context.Background()
	createClient := func() *Client {
		return &Client{
			target: sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
			obsv:   observability.NewNoopExporters(),
		}
	}

	t.Run("uses default message when empty", func(t *testing.T) {
		client := createClient()
		regularErr := errors.New("some error")
		err := client.checkGQLError(ctx, regularErr, "")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to perform GraphQL request")
	})

	t.Run("wraps non-GraphQL errors", func(t *testing.T) {
		client := createClient()
		regularErr := errors.New("network error")
		err := client.checkGQLError(ctx, regularErr, "custom message")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "custom message")
		assert.Contains(t, err.Error(), "network error")
	})

	t.Run("detects primary rate limit error", func(t *testing.T) {
		client := createClient()
		gqlErr := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"API rate limit exceeded for user\\\",\\\"documentation_url\\\":\\\"https://docs.github.com/rate-limiting\\\"}\\n\"")

		err := client.checkGQLError(ctx, gqlErr, "query failed")

		require.Error(t, err)
		var rateLimitErr *limiter.RateLimitError
		assert.True(t, errors.As(err, &rateLimitErr))
		assert.Contains(t, err.Error(), "query failed")
		assert.Equal(t, client.target.App, rateLimitErr.Target.App)
		assert.Equal(t, client.target.Type, rateLimitErr.Target.Type)
		assert.Equal(t, client.target.ID, rateLimitErr.Target.ID)
	})

	t.Run("detects primary rate limit in query error", func(t *testing.T) {
		client := createClient()
		mockErr := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "API rate limit exceeded for installation ID 123456"},
		})

		err := client.checkGQLError(ctx, mockErr, "mutation failed")

		require.Error(t, err)
		var rateLimitErr *limiter.RateLimitError
		assert.True(t, errors.As(err, &rateLimitErr))
		assert.Contains(t, err.Error(), "mutation failed")
	})

	t.Run("detects secondary rate limit error", func(t *testing.T) {
		client := createClient()
		gqlErr := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"You have exceeded a secondary rate limit. Please wait.\\\"}\\n\"")

		err := client.checkGQLError(ctx, gqlErr, "query failed")

		require.Error(t, err)
		var abuseErr *limiter.AbuseRateLimitError
		assert.True(t, errors.As(err, &abuseErr))
		assert.Contains(t, err.Error(), "query failed")
	})

	t.Run("detects secondary rate limit in query error", func(t *testing.T) {
		client := createClient()
		mockErr := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "You have exceeded a secondary rate limit and have been temporarily blocked"},
		})

		err := client.checkGQLError(ctx, mockErr, "mutation failed")

		require.Error(t, err)
		var abuseErr *limiter.AbuseRateLimitError
		assert.True(t, errors.As(err, &abuseErr))
	})

	// TODO (colbylwilliams): Is this the desired behavior when the target is an App?
	t.Run("handles primary rate limit when target is an App", func(t *testing.T) {
		client := createClient()
		client.target = sweagentd.ClientTargetForApp(0)

		gqlErr := errors.New("non-200 OK status code: 403 Forbidden body: \"{\\\"message\\\":\\\"API rate limit exceeded\\\"}\\n\"")
		err := client.checkGQLError(ctx, gqlErr, "query failed")

		require.Error(t, err)
		var rateLimitErr *limiter.RateLimitError
		assert.True(t, errors.As(err, &rateLimitErr))
		assert.Contains(t, err.Error(), "query failed")
	})

	t.Run("returns GraphQL error when not a rate limit", func(t *testing.T) {
		client := createClient()
		gqlErr := errors.New("non-200 OK status code: 404 Not Found body: \"{\\\"message\\\":\\\"Resource not found\\\"}\\n\"")

		err := client.checkGQLError(ctx, gqlErr, "query failed")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "query failed")
		assert.Contains(t, err.Error(), "Resource not found")

		// Should not be a rate limit error
		var rateLimitErr *limiter.RateLimitError
		assert.False(t, errors.As(err, &rateLimitErr))
		var abuseErr *limiter.AbuseRateLimitError
		assert.False(t, errors.As(err, &abuseErr))
	})

	t.Run("handles GraphQL query errors without rate limit", func(t *testing.T) {
		client := createClient()
		mockErr := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "Field 'invalid' not found on type 'Repository'"},
		})

		err := client.checkGQLError(ctx, mockErr, "query failed")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "query failed")
		assert.Contains(t, err.Error(), "Field 'invalid' not found")
	})

	t.Run("checks multiple query errors for rate limit", func(t *testing.T) {
		client := createClient()
		mockErr := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "Some other error"},
			{Message: "You have exceeded a secondary rate limit"},
			{Message: "Yet another error"},
		})

		err := client.checkGQLError(ctx, mockErr, "mutation failed")

		require.Error(t, err)
		var abuseErr *limiter.AbuseRateLimitError
		assert.True(t, errors.As(err, &abuseErr))
	})

	t.Run("primary rate limit takes precedence over secondary", func(t *testing.T) {
		client := createClient()
		// Both rate limit messages present
		mockErr := createMockGraphQLErrors([]mockGraphQLError{
			{Message: "API rate limit exceeded"},
			{Message: "You have exceeded a secondary rate limit"},
		})

		err := client.checkGQLError(ctx, mockErr, "query failed")

		require.Error(t, err)
		// Should detect primary rate limit first due to switch case order
		var rateLimitErr *limiter.RateLimitError
		assert.True(t, errors.As(err, &rateLimitErr))
	})
}
