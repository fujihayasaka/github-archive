package observability

import (
	"context"
	"errors"
	"net/http"
	"reflect"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// contextKey is a custom type for context keys to avoid collisions
type contextKey string

// TestLoggerWithTelemetry tests the LoggerWithTelemetry function
func TestLoggerWithTelemetry(t *testing.T) {
	// Create a mock telemetry function
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		return stats.Tags{"key": "value"}, map[string]string{"ex": "value"}, []kvp.Field{kvp.String("field", "value")}
	}

	// Test with nil telemetry function
	t.Run("nil telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		logger := exporters.LoggerWithTelemetry(context.Background())

		require.NotNil(t, logger)
	})

	// Test with mock telemetry function
	t.Run("with telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		logger := exporters.LoggerWithTelemetry(context.Background())

		require.NotNil(t, logger)
	})
}

// TestLoggerWithTelemetryWithEnrichedContext tests LoggerWithTelemetry with context enrichment
func TestLoggerWithTelemetryWithEnrichedContext(t *testing.T) {
	// Create a context with some values
	ctx := context.WithValue(context.Background(), contextKey("test-key"), "test-value")

	// Mock telemetry function that uses context values
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		var fields []kvp.Field
		if v, ok := ctx.Value(contextKey("test-key")).(string); ok {
			fields = append(fields, kvp.String("context-value", v))
		}
		return stats.Tags{"ctx": "exists"}, map[string]string{"ctx": "exists"}, fields
	}

	exporters := NewNoopExporters()
	exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)

	// This should extract the context-value field from the context
	logger := exporters.LoggerWithTelemetry(ctx)
	require.NotNil(t, logger)
}

// TestLoggerWithRequestTelemetry tests the LoggerWithRequestTelemetry function
func TestLoggerWithRequestTelemetry(t *testing.T) {
	// Create a mock request
	req, err := http.NewRequest("GET", "http://example.com", nil)
	require.NoError(t, err)

	// Create a mock telemetry function
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		// Verify that the request is passed correctly
		if r != nil {
			assert.Equal(t, "GET", r.Method)
		}
		return stats.Tags{"key": "value"}, map[string]string{"ex": "value"}, []kvp.Field{kvp.String("field", "value")}
	}

	// Test with nil telemetry function
	t.Run("nil telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		logger := exporters.LoggerWithRequestTelemetry(context.Background(), req)

		require.NotNil(t, logger)
	})

	// Test with mock telemetry function
	t.Run("with telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		logger := exporters.LoggerWithRequestTelemetry(context.Background(), req)

		require.NotNil(t, logger)
	})
}

// TestLoggerWithRequestTelemetryWithHeaders tests LoggerWithRequestTelemetry with HTTP headers
func TestLoggerWithRequestTelemetryWithHeaders(t *testing.T) {
	// Create a request with custom headers
	req, err := http.NewRequest("GET", "http://example.com", nil)
	require.NoError(t, err)
	req.Header.Set("X-Custom-Header", "custom-value")
	req.Header.Set("Authorization", "Bearer token")

	// Mock telemetry function that extracts headers
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		var fields []kvp.Field
		if r != nil {
			fields = append(fields, kvp.String("request-header", r.Header.Get("X-Custom-Header")))
			// Don't include sensitive headers like Authorization
		}
		return stats.Tags{}, map[string]string{}, fields
	}

	exporters := NewNoopExporters()
	exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)

	logger := exporters.LoggerWithRequestTelemetry(context.Background(), req)
	require.NotNil(t, logger)
}

// classifiedError is a test error type that implements the Class() method
type classifiedError struct {
	msg   string
	class string
}

func (e *classifiedError) Error() string {
	return e.msg
}

func (e *classifiedError) Class() string {
	return e.class
}

// TestLogAndReportError tests the LogAndReportError function
func TestLogAndReportError(t *testing.T) {
	testErr := errors.New("test error")

	// Create a mock telemetry function
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		return stats.Tags{"key": "value"}, map[string]string{"ex": "value"}, []kvp.Field{kvp.String("field", "value")}
	}

	// Test with nil error and empty message
	t.Run("nil error and empty message", func(t *testing.T) {
		exporters := NewNoopExporters()
		// This should be a no-op and not panic
		exporters.LogAndReportError(context.Background(), nil, "")
	})

	// Test with nil error but with message
	t.Run("nil error with message", func(t *testing.T) {
		exporters := NewNoopExporters()
		// Should not panic
		exporters.LogAndReportError(context.Background(), nil, "test message")
	})

	// Test with error but no telemetry function
	t.Run("error without telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		// Should not panic
		exporters.LogAndReportError(context.Background(), testErr, "test message")
	})

	// Test with error and telemetry function
	t.Run("error with telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		// Should not panic
		exporters.LogAndReportError(context.Background(), testErr, "test message")
	})

	// Test with error that has Class() method and no telemetry function
	t.Run("classified error without telemetry function", func(t *testing.T) {
		classErr := &classifiedError{
			msg:   "classified test error",
			class: "TestErrorClass",
		}
		exporters := NewNoopExporters()
		// Should not panic and should add class to exceptions
		exporters.LogAndReportError(context.Background(), classErr, "test message with class")
	})

	// Test with error that has Class() method and telemetry function
	t.Run("classified error with telemetry function", func(t *testing.T) {
		classErr := &classifiedError{
			msg:   "classified test error",
			class: "TestErrorClass",
		}
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		// Should not panic and should merge class with telemetry exceptions
		exporters.LogAndReportError(context.Background(), classErr, "test message with class")
	})

	// Test with regular error (no Class method) to ensure it doesn't break
	t.Run("regular error without Class method", func(t *testing.T) {
		regularErr := errors.New("regular error without class")
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		// Should not panic and should only use telemetry exceptions
		exporters.LogAndReportError(context.Background(), regularErr, "test message")
	})

	// Test with error that has empty Class() return value
	t.Run("error with empty class", func(t *testing.T) {
		emptyClassErr := &classifiedError{
			msg:   "error with empty class",
			class: "",
		}
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		// Should not panic; empty class should not be added
		exporters.LogAndReportError(context.Background(), emptyClassErr, "test message")
	})
}

// TestTelemetryTags tests the TelemetryTags function
func TestTelemetryTags(t *testing.T) {
	expectedTags := stats.Tags{"key": "value"}

	// Create a mock telemetry function
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		return expectedTags, map[string]string{"ex": "value"}, []kvp.Field{kvp.String("field", "value")}
	}

	// Test with nil telemetry function
	t.Run("nil telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		tags := exporters.TelemetryTags(context.Background())

		// Should return empty tags
		assert.Empty(t, tags)
	})

	// Test with mock telemetry function
	t.Run("with telemetry function", func(t *testing.T) {
		exporters := NewNoopExporters()
		exporters = exporters.WithTelemetryFunc(mockTelemetryFunc)
		tags := exporters.TelemetryTags(context.Background())

		// Should return expected tags
		assert.True(t, reflect.DeepEqual(expectedTags, tags), "Tags do not match expected value")
		assert.Equal(t, "value", tags["key"])
	})
}

// TestWithTelemetryFunc tests the WithTelemetryFunc function
func TestWithTelemetryFunc(t *testing.T) {
	mockTelemetryFunc := func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
		return stats.Tags{"key": "value"}, map[string]string{"ex": "value"}, []kvp.Field{kvp.String("field", "value")}
	}

	exporters := NewNoopExporters()
	// Verify telemetryFunc is initially nil
	assert.Nil(t, exporters.telemetryFunc)

	// Call WithTelemetryFunc
	newExporters := exporters.WithTelemetryFunc(mockTelemetryFunc)

	// Verify telemetryFunc was set
	assert.NotNil(t, newExporters.telemetryFunc)

	// Test that the function is actually callable
	tags, ex, fields := newExporters.telemetryFunc(context.Background(), nil)
	assert.Equal(t, "value", tags["key"])
	assert.Equal(t, "value", ex["ex"])
	assert.Len(t, fields, 1)
	assert.Equal(t, "field", fields[0].Key)
}

// TestHydrateTelemetryFunc tests different implementations of the HydrateTelemetryFunc type
func TestHydrateTelemetryFunc(t *testing.T) {
	t.Run("basic implementation", func(t *testing.T) {
		var fn HydrateTelemetryFunc = func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
			return stats.Tags{"test": "tag"}, map[string]string{"test": "exception"}, []kvp.Field{kvp.String("test", "field")}
		}

		tags, exceptions, fields := fn(context.Background(), nil)

		assert.Equal(t, "tag", tags["test"])
		assert.Equal(t, "exception", exceptions["test"])
		assert.Len(t, fields, 1)
		assert.Equal(t, "test", fields[0].Key)
	})

	t.Run("with request", func(t *testing.T) {
		req, err := http.NewRequest("POST", "http://example.com/test", nil)
		require.NoError(t, err)

		var fn HydrateTelemetryFunc = func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
			if r != nil {
				return stats.Tags{"method": r.Method, "path": r.URL.Path},
					map[string]string{"url": r.URL.String()},
					[]kvp.Field{kvp.String("method", r.Method)}
			}
			return stats.Tags{}, map[string]string{}, []kvp.Field{}
		}

		tags, exceptions, fields := fn(context.Background(), req)

		assert.Equal(t, "POST", tags["method"])
		assert.Equal(t, "/test", tags["path"])
		assert.Equal(t, "http://example.com/test", exceptions["url"])
		assert.Len(t, fields, 1)
		assert.Equal(t, "method", fields[0].Key)
	})

	t.Run("nil request handling", func(t *testing.T) {
		var fn HydrateTelemetryFunc = func(ctx context.Context, r *http.Request) (stats.Tags, map[string]string, []kvp.Field) {
			if r == nil {
				return stats.Tags{"request": "nil"}, map[string]string{"request": "nil"}, []kvp.Field{kvp.String("request", "nil")}
			}
			return stats.Tags{}, map[string]string{}, []kvp.Field{}
		}

		tags, exceptions, fields := fn(context.Background(), nil)

		assert.Equal(t, "nil", tags["request"])
		assert.Equal(t, "nil", exceptions["request"])
		assert.Len(t, fields, 1)
		assert.Equal(t, "request", fields[0].Key)
	})
}
