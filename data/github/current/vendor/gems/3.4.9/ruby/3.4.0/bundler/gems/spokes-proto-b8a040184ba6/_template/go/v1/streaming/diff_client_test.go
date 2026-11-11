package streaming

import (
	"bytes"
	"io"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestReadRawDiffHTTPRequest(t *testing.T) {
	examples := []struct {
		name        string
		req         *ReadRawDiffRequest
		baseURL     string
		expectedURL string
		expectError bool
	}{
		{
			name: "basic diff request",
			req: &ReadRawDiffRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				Oid1: &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
				Oid2: &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
				FullIndex: false,
				Mode: ReadRawDiffRequest_DIFF_MODE_PATCH,
			},
			baseURL:     "http://example.com",
			expectedURL: "http://example.com/streaming/v1/diffs/raw",
		},
		{
			name: "root diff request",
			req: &ReadRawDiffRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				Oid1: &ReadRawDiffRequest_RootSelector1{},
				Oid2: &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
				FullIndex: true,
				Mode: ReadRawDiffRequest_DIFF_MODE_DIFF,
			},
			baseURL:     "http://example.com",
			expectedURL: "http://example.com/streaming/v1/diffs/raw",
		},
		{
			name: "incomplete baseURL",
			req: &ReadRawDiffRequest{
				Repository:     repository,
				RequestContext: reqCtx,
				Oid1: &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
				Oid2: &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
				FullIndex: false,
				Mode: ReadRawDiffRequest_DIFF_MODE_PATCH,
			},
			baseURL:     "example.com",
			expectedURL: "http://example.com/streaming/v1/diffs/raw",
		},
		{
			name:        "nil request",
			req:         nil,
			baseURL:     "http://example.com",
			expectError: true,
		},
	}

	for _, example := range examples {
		t.Run(example.name, func(t *testing.T) {
			req, err := NewReadRawDiffHTTPRequest(example.req, example.baseURL)
			if example.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, "POST", req.Method)
				assert.Equal(t, example.expectedURL, req.URL.String())
				assert.Equal(t, "application/protobuf", req.Header.Get("Content-Type"))
				assert.Equal(t, "application/octet-stream", req.Header.Get("Accept"))
				assertFirstByte(t, 0xa, req.Body)
			}
		})
	}
}

func TestReadRawDiffHTTPRequestCustom(t *testing.T) {
	rdr := &ReadRawDiffRequest{
		Repository:     repository,
		RequestContext: reqCtx,
		Oid1: &ReadRawDiffRequest_ObjectId1{ObjectId1: oid1},
		Oid2: &ReadRawDiffRequest_ObjectId2{ObjectId2: oid2},
		FullIndex: false,
		Mode: ReadRawDiffRequest_DIFF_MODE_PATCH,
	}

	t.Run("protobuf request", func(t *testing.T) {
		req, err := NewReadRawDiffHTTPRequestCustom(rdr, "http://example.com", ProtobufContentType, "application/octet-stream")
		require.NoError(t, err)
		assert.Equal(t, "POST", req.Method)
		assert.Equal(t, "http://example.com/streaming/v1/diffs/raw", req.URL.String())
		assert.Equal(t, "application/protobuf", req.Header.Get("Content-Type"))
		assert.Equal(t, "application/octet-stream", req.Header.Get("Accept"))
		assertFirstByte(t, 0xa, req.Body)
	})

	t.Run("json request", func(t *testing.T) {
		req, err := NewReadRawDiffHTTPRequestCustom(rdr, "http://example.com", JSONContentType, "application/octet-stream")
		require.NoError(t, err)
		assert.Equal(t, "POST", req.Method)
		assert.Equal(t, "http://example.com/streaming/v1/diffs/raw", req.URL.String())
		assert.Equal(t, "application/json", req.Header.Get("Content-Type"))
		assert.Equal(t, "application/octet-stream", req.Header.Get("Accept"))
		assertFirstByte(t, '{', req.Body)
	})

	t.Run("unsupported request content type", func(t *testing.T) {
		_, err := NewReadRawDiffHTTPRequestCustom(rdr, "http://example.com", "application/xml", "application/octet-stream")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unsupported request content type")
	})

	t.Run("unsupported response content type", func(t *testing.T) {
		_, err := NewReadRawDiffHTTPRequestCustom(rdr, "http://example.com", JSONContentType, "application/json")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unsupported response content type")
	})
}

func TestGetReadRawDiffResponse(t *testing.T) {
	examples := []struct {
		name             string
		statusCode       int
		contentType      string
		respBody         []byte
		expectedErrorMsg string
	}{
		{
			name:             "reads 200 response",
			statusCode:       http.StatusOK,
			contentType:      "application/octet-stream",
			respBody:         []byte("diff --git a/README.md b/README.md"),
		},
		{
			name:             "reads non-200 response",
			statusCode:       http.StatusBadRequest,
			contentType:      "application/json",
			respBody:         []byte("{\"code\":\"invalid_argument\",\"msg\":\"invalid argument\"}"),
			expectedErrorMsg: "invalid argument",
		},
		{
			name:             "unexpected Content-Type",
			statusCode:       http.StatusOK,
			contentType:      "application/json",
			respBody:         []byte("{\"key\":\"value\"}"),
			expectedErrorMsg: "unexpected response content-type \"application/json\"",
		},
	}

	for _, example := range examples {
		t.Run(example.name, func(t *testing.T) {
			resp := &http.Response{
				StatusCode: example.statusCode,
				Header:     http.Header{},
				Body:       io.NopCloser(bytes.NewReader(example.respBody)),
			}
			resp.Header.Set("Content-Type", example.contentType)

			respBody, err := GetReadRawDiffResponse(resp)

			if example.expectedErrorMsg != "" {
				require.Error(t, err)
				twerr, ok := err.(twirp.Error)
				require.True(t, ok, "expected twirp error")
				require.Equal(t, string(example.expectedErrorMsg), twerr.Msg())
			} else {
				require.NoError(t, err)
				assert.Equal(t, example.respBody, respBody)
			}
		})
	}
}
