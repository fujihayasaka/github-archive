package feature

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type assertionHandler struct {
	assert func(r *http.Request)
}

func (h assertionHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.assert(r)
	w.WriteHeader(http.StatusOK)
}

func TestHandlerWithFeatures(t *testing.T) {
	var called bool
	ah := assertionHandler{
		assert: func(r *http.Request) {
			called = true
			assert.True(t, Enabled(r.Context(), "feature1"))
			assert.True(t, Enabled(r.Context(), "feature2"))
			assert.False(t, Enabled(r.Context(), "feature3"))
		},
	}

	features := []string{"feature1", "feature2"}
	serialized, err := json.Marshal(features)
	require.NoError(t, err)
	encoded := base64.StdEncoding.EncodeToString(serialized)

	h := Handler(ah)
	req, err := http.NewRequest("GET", "/", nil)
	require.NoError(t, err)
	req.Header.Set(HeaderName, encoded)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.True(t, called)
}

func TestHandlerNoFeatures(t *testing.T) {
	var called bool
	ah := assertionHandler{
		assert: func(r *http.Request) {
			called = true
			assert.False(t, Enabled(r.Context(), "feature1"))
			assert.False(t, Enabled(r.Context(), "feature2"))
			assert.False(t, Enabled(r.Context(), "feature3"))
		},
	}

	h := Handler(ah)
	req, err := http.NewRequest("GET", "/", nil)
	require.NoError(t, err)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.True(t, called)
}
