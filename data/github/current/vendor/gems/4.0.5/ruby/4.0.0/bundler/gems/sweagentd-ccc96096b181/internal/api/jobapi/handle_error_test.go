package jobapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"syscall"
	"testing"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestErrorResponseWithError(t *testing.T) {
	t.Run("sets appropriate HTTP status code and content type", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		handler := &Handler{obsv: obsv}

		ctx := context.Background()
		w := httptest.NewRecorder()
		logger := obsv.Logger

		err := handler.errorResponseWithError(ctx, w, nil, logger, errors.New("test error"), "test message")

		require.NoError(t, err)
		require.Equal(t, 500, w.Code)
		require.Equal(t, "text/plain; charset=utf-8", w.Header().Get("Content-Type"))
	})

	t.Run("checks for SessionResponseError and sets appropriate HTTP status code", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		handler := &Handler{obsv: obsv}

		ctx := context.Background()
		w := httptest.NewRecorder()
		logger := obsv.Logger

		// url.Error is what wraps SessionResponseError with the retry client we use
		urlErr := &url.Error{
			Op:  "Get",
			URL: "http://example.com",
			Err: &joberrors.SessionResponseError{
				StatusCode: 401,
				Body:       "foo",
			},
		}

		jobErr := fmt.Errorf("failed to create session for job: %w", fmt.Errorf("failed to create session: %w", urlErr))
		err := handler.errorResponseWithError(ctx, w, nil, logger, jobErr, "test message")

		require.NoError(t, err)
		require.Equal(t, 401, w.Code)
		require.Equal(t, "text/plain; charset=utf-8", w.Header().Get("Content-Type"))
	})

	t.Run("checks for CAPIError and sets appropriate HTTP status code", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		handler := &Handler{obsv: obsv}

		ctx := context.Background()
		w := httptest.NewRecorder()
		logger := obsv.Logger

		err := handler.errorResponseWithError(ctx, w, nil, logger, &joberrors.CAPIError{Response: &http.Response{StatusCode: http.StatusTooManyRequests}, Message: "capi error"}, "test message")

		require.NoError(t, err)
		require.Equal(t, 429, w.Code)
		require.Equal(t, "text/plain; charset=utf-8", w.Header().Get("Content-Type"))
	})

	t.Run("checks for ECONNRESET and sets status code 499 with context cancelled message", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		handler := &Handler{obsv: obsv}

		ctx := context.Background()
		w := httptest.NewRecorder()
		logger := obsv.Logger

		err := handler.errorResponseWithError(ctx, w, nil, logger, syscall.ECONNRESET, "test message")

		require.NoError(t, err)
		require.Equal(t, 499, w.Code)
		require.Equal(t, "text/plain; charset=utf-8", w.Header().Get("Content-Type"))

		var errResponse gg.ErrorResponse
		err = json.Unmarshal(w.Body.Bytes(), &errResponse)
		require.NoError(t, err)
		require.Equal(t, "context cancelled", errResponse.Message)
	})
}
