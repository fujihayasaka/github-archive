package jobapi

import (
	"context"
	"errors"
	"fmt"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
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
}
