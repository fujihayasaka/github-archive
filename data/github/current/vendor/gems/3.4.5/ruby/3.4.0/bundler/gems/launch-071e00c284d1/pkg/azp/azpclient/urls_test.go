package azpclient

import (
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestArtifactCacheListURL(t *testing.T) {
	u := newURLBuilder()
	key := "a b"
	scope := "refs/heads/main"
	sort := "lastAccessedAt"
	direction := "desc"
	var page, perPage int64
	page = 1
	perPage = 30

	uri := u.getListCacheURL(key, scope, sort, direction, page, perPage)
	escapedKey := url.QueryEscape(key)
	escapedScope := url.QueryEscape(scope)
	assert.Equal(t, true, strings.Contains(uri, escapedKey))
	assert.Equal(t, true, strings.Contains(uri, escapedScope))
}

func TestArtifactCacheDeleteByKeyUrl(t *testing.T) {
	u := newURLBuilder()
	key := "a b"
	scope := "refs/heads/main"

	uri := u.getDeleteCachesByKeyURL(key, scope)
	escapedKey := url.QueryEscape(key)
	escapedScope := url.QueryEscape(scope)
	assert.Equal(t, true, strings.Contains(uri, escapedKey))
	assert.Equal(t, true, strings.Contains(uri, escapedScope))
}

func TestGetListRunnerGroupsURL(t *testing.T) {
	u := newURLBuilder()
	uri := u.getListRunnerGroupsURL(
		true,
		"owner-id",
		"parent-id",
		"parent-tenant-name",
		true,
		true,
		true,
		true,
	)

	result, err := url.Parse(uri)
	require.NoError(t, err)

	q := result.Query()

	expectedQueryValues := map[string]string{
		"api-version":               "6.0-preview",
		"includeRunners":            "true",
		"currentTenant":             "owner-id",
		"isCurrentTenantEnterprise": "true",
		"excludeHostedRunnerGroups": "true",
		"includeVisibility":         "true",
		"excludeElasticRunners":     "true",
		"includeRunnerScaleSets":    "true",
	}

	for query, value := range expectedQueryValues {
		assert.Equal(t, value, q.Get(query), "query %s", query)
	}
}

func TestGetRunnerScaleSetURL(t *testing.T) {
	u := newURLBuilder()
	uri := u.getRunnerScaleSetURL(42)

	result, err := url.Parse(uri)
	require.NoError(t, err)

	assert.True(t, strings.HasSuffix(result.Path, "/_apis/runtime/runnerscalesets/42"))

	q := result.Query()

	assert.Equal(t, "6.0-preview", q.Get("api-version"))
}

func TestGetRunnerScaleSetsURL(t *testing.T) {
	u := newURLBuilder()
	uri := u.getRunnerScaleSetsURL(true)

	result, err := url.Parse(uri)
	require.NoError(t, err)

	assert.True(t, strings.HasSuffix(result.Path, "/_apis/runtime/runnerscalesets"))

	q := result.Query()

	assert.Equal(t, "6.0-preview", q.Get("api-version"))
	assert.Equal(t, "true", q.Get("excludeElasticRunners"))
}

func TestGetRunnerGroupURLbyGroupIDFor(t *testing.T) {
	u := newURLBuilder()
	uri := u.getRunnerGroupURLbyGroupIDFor(
		42,
		"owner-id",
		"parent-id",
		"parent-tenant-name",
		true,
		true,
		true,
		true,
		true,
	)

	result, err := url.Parse(uri)
	require.NoError(t, err)

	assert.True(t, strings.HasSuffix(result.Path, "/_apis/runtime/runnergroups/42"))

	q := result.Query()

	expectedQueryValues := map[string]string{
		"api-version":               "6.0-preview",
		"includeRunners":            "true",
		"currentTenant":             "owner-id",
		"isCurrentTenantEnterprise": "true",
		"excludeHostedRunnerGroups": "true",
		"includeVisibility":         "true",
		"excludeElasticRunners":     "true",
		"includeRunnerScaleSets":    "true",
	}

	for query, value := range expectedQueryValues {
		assert.Equal(t, value, q.Get(query), "query %s", query)
	}
}

func TestGetListRunnersV2URL(t *testing.T) {
	u := newURLBuilder()
	uri := u.getListRunnersV2URL(
		1,
		1,
		10,
		true,
		"",
		false,
	)

	result, err := url.Parse(uri)
	require.NoError(t, err)

	q := result.Query()
	expectedQueryValues := map[string]string{
		"api-version":            "6.0-preview",
		"page":                   "1",
		"perPage":                "10",
		"includeAssignedRequest": "true",
	}

	for query, value := range expectedQueryValues {
		assert.Equal(t, value, q.Get(query), "query %s", query)
	}

	uri2 := u.getListRunnersV2URL(
		1,
		1,
		10,
		true,
		"test runner",
		true,
	)

	result2, err := url.Parse(uri2)
	require.NoError(t, err)

	q2 := result2.Query()
	expectedQueryValues2 := map[string]string{
		"api-version":            "6.0-preview",
		"page":                   "1",
		"perPage":                "10",
		"includeAssignedRequest": "true",
		"agentName":              "test runner",
		"excludeElasticRunners":  "true",
	}

	for query, value := range expectedQueryValues2 {
		assert.Equal(t, value, q2.Get(query), "query %s", query)
	}
}

func newURLBuilder() *urlBuilder {
	return &urlBuilder{
		repoBaseURL:           "https://pipelines.actions.githubusercontent.com",
		acServiceBaseURL:      "https://artifactcache.actions.githubusercontent.com",
		runnersServiceBaseURL: "https://runner.actions.githubusercontent.com",
		repoExternalBaseURL:   "https://pipelines.actions.githubusercontent.com",
		tenantName:            "test-org",
		projectName:           "tes-project",
		pipelineID:            1,
	}
}
