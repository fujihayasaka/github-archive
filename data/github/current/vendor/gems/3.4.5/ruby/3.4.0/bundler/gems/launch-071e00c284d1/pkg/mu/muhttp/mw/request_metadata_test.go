package mw_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	gokvp "github.com/github/go-kvp"
	"github.com/stretchr/testify/assert"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"
)

type rmdHandler struct {
	Request *http.Request
}

func (h *rmdHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.Request = r
}

func TestRequestMetadataNilContext(t *testing.T) {
	rmd := mw.GetRequestMetadata(nil) // nolint: staticcheck, megacheck

	assert.Nil(t, rmd)
}

func TestRequestMetadataNotInContext(t *testing.T) {
	rmd := mw.GetRequestMetadata(context.Background())

	assert.Nil(t, rmd)
}

func TestRequestMetadataLogWith(t *testing.T) {
	rmd := reqmeta.NewRequestMetadata()
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, rmd)

	mw.LogWith(ctx, gokvp.String("foo", "bar"))

	assert.Len(t, rmd.LogFields(), 1)
}

func TestRequestMetadataTagStatsWith(t *testing.T) {
	rmd := reqmeta.NewRequestMetadata()
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, rmd)

	mw.TagStatsWith(ctx, reqmeta.Tags{"foo": "bar"})

	assert.Len(t, rmd.StatTags(), 1)
}

func TestRequestMetadataDefaults(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "<none>",
		"gh.auth.method":  "<none>",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithRequestID(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("X-GitHub-Request-Id", "123")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   "123",
		"http.user_agent": "<none>",
		"gh.auth.method":  "<none>",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithUserAgent(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("User-Agent", "james-bond")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "james-bond",
		"gh.auth.method":  "<none>",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithBasicAuth(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("Authorization", "basic bW9ua2V5OmJhZA==")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "<none>",
		"gh.auth.method":  "basic",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithRemoteAuth(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("Authorization", "remoteauth bW9ua2V5OmJhZA==")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "<none>",
		"gh.auth.method":  "remoteauth",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithMultiWordAuth(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("Authorization", "digest whatever")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "<none>",
		"gh.auth.method":  "<unknown>",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func TestRequestMetadataWithSingleWordAuth(t *testing.T) {
	h := &rmdHandler{}
	fn := mw.GitHubRequestID(mw.RequestMetadata(reqmeta.NewRequestMetadata())(h))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/foo", nil)
	req.Header.Set("Authorization", "basic")
	fn.ServeHTTP(w, req)

	assert.NotNil(t, h.Request)

	rid := mw.GetGitHubRequestID(h.Request.Context())
	assert.NotEmpty(t, rid)

	expected := map[string]string{
		"http.method":     http.MethodGet,
		"http.url":        "/foo",
		"gh.request_id":   rid,
		"http.user_agent": "<none>",
		"gh.auth.method":  "<unknown>",
	}

	assert.Equal(t, expected, getFields(h.Request))
}

func getFields(r *http.Request) map[string]string {
	fields := make(map[string]string)
	k := mw.GetRequestMetadata(r.Context()).LogFields()
	for _, f := range k {
		fields[f.Key] = f.String()
	}
	return fields
}
