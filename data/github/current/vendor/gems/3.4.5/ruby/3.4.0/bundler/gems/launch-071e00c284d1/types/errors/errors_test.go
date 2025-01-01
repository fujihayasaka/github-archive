package errors

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
)

func TestHttpError_CleanURL(t *testing.T) {
	tests := []struct {
		desc        string
		url         string
		expectedURL string
	}{
		{
			desc:        "finds IDs in urls",
			url:         "https://internal-api.service.iad.github.net/repositories/187652344/installation",
			expectedURL: "https://internal-api.service.iad.github.net/repositories/***/installation",
		},
		{
			desc:        "does nothing otherwise",
			url:         "https://internal-api.service.iad.github.net/getSomething",
			expectedURL: "https://internal-api.service.iad.github.net/getSomething",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.url, nil)
			resp := &http.Response{
				Body:       io.NopCloser(bytes.NewBufferString("Hello World")),
				Status:     "200 OK",
				StatusCode: 200,
				Request:    req,
			}
			err := NewHTTPError(resp)

			assert.Equal(t, fmt.Sprintf("unexpected response `200` from `%s`", tt.expectedURL), err.Error())
		})
	}
}

func TestGraphqlError_CleanMessage(t *testing.T) {
	tests := []struct {
		desc string
		err  string
	}{
		{
			desc: "finds one ID style",
			err:  "Something went wrong while executing your query. Please include `7a066b572431f54181ead6619cb6b454` when reporting this issue.",
		},
		{
			desc: "finds another ID style",
			err:  "Something went wrong while executing your query. Please include `0401:B462:E560A07:15208BE3:5F593141` when reporting this issue.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			err := NewGraphQLError(errors.New(tt.err))
			assert.Contains(t, err.Error(), "Please include <request-id>")
			assert.NotContains(t, err.Error(), tt.err)
		})
	}
}

func Test_ErrorsAreRetryable(t *testing.T) {
	tests := []struct {
		name string
		err  error
	}{
		{
			name: "Basic retryable error",
			err:  NewRetryable("database timeout"),
		},
		{
			name: "Retryable error wrapping another error",
			err:  WrapAsRetryable(errors.New("Row not found"), "Failed to read build from the database"),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.True(tt, IsRetryable(tc.err))
		})
	}
}

func TestIsInternalError(t *testing.T) {
	tests := []struct {
		name            string
		err             error
		isInternalError bool
	}{
		{
			name:            "basic internal error",
			err:             NewInternalError(errs.New("internal error")),
			isInternalError: true,
		},
		{
			name:            "wrapped internal error",
			err:             errs.Wrap(NewInternalError(errs.New("internal error")), "wrapping"),
			isInternalError: true,
		},
		{
			name:            "not internal error",
			err:             errs.New("not internal error"),
			isInternalError: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(tt, tc.isInternalError, IsInternalError(tc.err))
		})
	}
}
