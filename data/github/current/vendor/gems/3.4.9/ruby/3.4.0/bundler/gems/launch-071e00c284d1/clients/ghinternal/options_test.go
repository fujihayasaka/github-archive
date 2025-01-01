package ghinternal

import (
	"bytes"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWithHMAC(t *testing.T) {
	fn := withHMAC([]byte("octocat"), func() time.Time {
		return time.Unix(1571417288, 0)
	})
	body := io.NopCloser(bytes.NewReader([]byte(`{"ids":["MDEwOlJlcG9zaXRvcnk3NQ=="]}`)))
	req := &http.Request{
		Header: http.Header{},
		Body:   body,
		GetBody: func() (closer io.ReadCloser, e error) {
			return body, nil
		},
	}
	require.NoError(t, fn(req))
	assert.Equal(t, "sha256 2e0ba704032edf5a1f71fbaf5d7473eb36f0c5d525b03f4c91d482a6bbaa121d", req.Header.Get("content-hmac"))
	assert.Equal(t, "1571417288.3f15899a54eb3ae261e2c73901b25fe6ded981d5bbd4da0db5fa8e480ea51be5", req.Header.Get("request-hmac"))
}
