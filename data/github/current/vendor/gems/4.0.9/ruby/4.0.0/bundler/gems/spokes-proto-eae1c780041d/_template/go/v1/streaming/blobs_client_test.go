package streaming

import (
	"io"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBlobHTTPRequest(t *testing.T) {
	validOID := "2ed9955df7613c630f68760160041bded358461a"

	examples := []struct {
		name        string
		repository  *types.Repository
		oid         *types.ObjectID
		baseURL     string
		expectedURL string
		expectError bool
	}{
		{
			name:        "repository",
			repository:  types.NewRepository(1),
			oid:         types.NewObjectID(validOID),
			baseURL:     "http://example.com",
			expectedURL: "http://example.com/streaming/v1/repositories/1/blobs/" + validOID,
		},
		{
			name:        "gist",
			repository:  types.NewGist(1),
			oid:         types.NewObjectID(validOID),
			baseURL:     "http://example.com",
			expectedURL: "http://example.com/streaming/v1/gists/1/blobs/" + validOID,
		},
		{
			name:        "wiki",
			repository:  types.NewWiki(1),
			oid:         types.NewObjectID(validOID),
			baseURL:     "http://example.com",
			expectError: true,
		},
		{
			name:        "incomplete baseURL",
			repository:  types.NewRepository(1),
			oid:         types.NewObjectID(validOID),
			baseURL:     "example.com",
			expectedURL: "http://example.com/streaming/v1/repositories/1/blobs/" + validOID,
		},
		{
			name:        "empty",
			expectError: true,
		},
	}

	for _, example := range examples {
		t.Run(example.name, func(t *testing.T) {
			req, err := NewBlobHTTPRequest(example.repository, example.oid, example.baseURL)
			if example.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, "GET", req.Method)
				assert.Equal(t, example.expectedURL, req.URL.String())
			}
		})
	}
}

func TestBatchBlobsHTTPRequest(t *testing.T) {
	bbr := NewBatchBlobsRequest(reqCtx, types.NewRepository(1), []*types.ObjectID{types.NewObjectID("abc123")})

	t.Run("simple request", func(t *testing.T) {
		req, err := NewBatchBlobsHTTPRequest(bbr, "http://example.com")
		require.NoError(t, err)
		assert.Equal(t, "POST", req.Method)
		assert.Equal(t, "http://example.com/streaming/v1/blobs", req.URL.String())
		assert.Equal(t, "application/protobuf", req.Header.Get("Content-Type"))
		assert.Equal(t, "application/tar", req.Header.Get("Accept"))
		assertFirstByte(t, 0xa, req.Body)
	})

	t.Run("custom request", func(t *testing.T) {
		req, err := NewBatchBlobsHTTPRequestCustom(bbr, "http://example.com", JSONContentType, TarContentType)
		require.NoError(t, err)
		assert.Equal(t, "POST", req.Method)
		assert.Equal(t, "http://example.com/streaming/v1/blobs", req.URL.String())
		assert.Equal(t, "application/json", req.Header.Get("Content-Type"))
		assert.Equal(t, "application/tar", req.Header.Get("Accept"))
		assertFirstByte(t, '{', req.Body)
	})
}

func assertFirstByte(t *testing.T, expected byte, r io.Reader) {
	var buf [1]byte
	n, err := r.Read(buf[:])
	assert.NoError(t, err)
	assert.Equal(t, 1, n)
	assert.Equal(t, expected, buf[0])
}
