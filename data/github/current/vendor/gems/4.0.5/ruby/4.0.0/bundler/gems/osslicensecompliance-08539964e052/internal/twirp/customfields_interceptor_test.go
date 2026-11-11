package twirp

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/cache/requestcache"
	"github.com/github/go-server/runtime/telemetry/customfields"
	"github.com/github/go-stats"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// nullReporter satisfies reporter.ExceptionReporter for tests where reporting
// behaviour is irrelevant; we only need the hook to install a reporter on ctx.
type nullReporter struct{}

func (nullReporter) Report(_ context.Context, _ error, _ map[string]string) error {
	return nil
}

func (nullReporter) ReportSensitive(_ context.Context, _ error, _, _ map[string]string) error {
	return nil
}

// fieldsFromInterceptor drives a request through CustomFieldsInterceptor and
// returns the resulting customfields slice.
func fieldsFromInterceptor(t *testing.T, req any) []customfields.Field {
	t.Helper()
	ctx := requestcache.WithEmptyCache(context.Background())
	called := false
	next := func(ctx context.Context, _ any) (any, error) {
		called = true
		return nil, nil
	}
	_, err := CustomFieldsInterceptor()(next)(ctx, req)
	require.NoError(t, err)
	assert.True(t, called, "interceptor must call next")
	return customfields.Fields(ctx)
}

func TestCustomFieldsInterceptor_CheckRepositoryRequest(t *testing.T) {
	req := &proto.CheckRepositoryRequest{
		RepositoryId:      111,
		OrganizationId:    222,
		EnterpriseId:      333,
		PullRequestId:     444,
		PullRequestNumber: 5,
		ForkRepositoryId:  666,
		CommitSha:         "abcdef1",
		BaseSha:           "0123456",
		Context:           "distributed", // not in the map — must be ignored
	}

	got := fieldsFromInterceptor(t, req)

	assert.ElementsMatch(t, []customfields.Field{
		{Key: "repository_id", Value: "111", Tag: true},
		{Key: "organization_id", Value: "222", Tag: true},
		{Key: "enterprise_id", Value: "333", Tag: true},
		{Key: "pull_request_id", Value: "444", Tag: false},
		{Key: "pull_request_number", Value: "5", Tag: false},
		{Key: "fork_repository_id", Value: "666", Tag: false},
		{Key: "commit_sha", Value: "abcdef1", Tag: false},
		{Key: "base_sha", Value: "0123456", Tag: false},
	}, got)
}

func TestCustomFieldsInterceptor_AlertRemediationFields(t *testing.T) {
	// CreatePackageExceptionRequest has alert_number as a literal proto field
	// name, so it is picked up via the global mapping.
	req := &proto.CreatePackageExceptionRequest{
		RepositoryId: 1,
		AlertNumber:  7,
		UserId:       123,
	}

	got := fieldsFromInterceptor(t, req)

	assert.ElementsMatch(t, []customfields.Field{
		{Key: "repository_id", Value: "1", Tag: true},
		{Key: "alert_number", Value: "7", Tag: false},
		{Key: "user_id", Value: "123", Tag: true},
	}, got)
}

func TestCustomFieldsInterceptor_DismissByIdAlertID(t *testing.T) {
	req := &proto.RequestAlertDismissalByIdRequest{
		AlertId: 9001,
		UserId:  77,
	}

	got := fieldsFromInterceptor(t, req)

	assert.ElementsMatch(t, []customfields.Field{
		{Key: "alert_id", Value: "9001", Tag: false},
		{Key: "user_id", Value: "77", Tag: true},
	}, got)
}

func TestCustomFieldsInterceptor_ZeroValuesAreSkipped(t *testing.T) {
	req := &proto.CheckRepositoryRequest{} // all zero

	got := fieldsFromInterceptor(t, req)

	assert.Empty(t, got)
}

func TestCustomFieldsInterceptor_NonProtoRequestIsNoop(t *testing.T) {
	got := fieldsFromInterceptor(t, "not a proto message")
	assert.Empty(t, got)
}

func TestCustomFieldsInterceptor_NilRequestIsNoop(t *testing.T) {
	got := fieldsFromInterceptor(t, nil)
	assert.Empty(t, got)
}

func TestCustomFieldsInterceptor_NoRequestCacheDoesNotPanic(t *testing.T) {
	// Without requestcache.WithEmptyCache, customfields silently drops
	// values. The interceptor must still call next and must not panic.
	req := &proto.CheckRepositoryRequest{RepositoryId: 1}
	called := false
	next := func(ctx context.Context, _ any) (any, error) {
		called = true
		return nil, nil
	}
	_, err := CustomFieldsInterceptor()(next)(context.Background(), req)
	require.NoError(t, err)
	assert.True(t, called)
}

// TestCustomFieldsInterceptor_ComposedWithDefaultHooks proves that the
// reporterContextHook (RequestReceived) runs before the interceptor in the
// real chain order, so the interceptor sees a context with the requestcache
// installed and customfields actually land. This locks in the hook+interceptor
// ordering wired up by DefaultHooks + NewTwirpServer.
func TestCustomFieldsInterceptor_ComposedWithDefaultHooks(t *testing.T) {
	hooks, err := DefaultHooks(log.NewNullLogger(), nullReporter{}, stats.NullStatter)
	require.NoError(t, err)
	require.NotNil(t, hooks.RequestReceived, "DefaultHooks must install a RequestReceived hook")

	ctx, err := hooks.RequestReceived(context.Background())
	require.NoError(t, err)

	// Sanity: the requestcache must be present after RequestReceived; if it
	// weren't, customfields.AddTag would silently drop values.
	_, _, err = requestcache.Get[struct{}](ctx, "telemetry_interceptor_test_probe")
	require.NoError(t, err, "RequestReceived must install a requestcache")

	req := &proto.CheckRepositoryRequest{RepositoryId: 42, OrganizationId: 7}
	called := false
	next := func(_ context.Context, _ any) (any, error) {
		called = true
		return nil, nil
	}
	_, err = CustomFieldsInterceptor()(next)(ctx, req)
	require.NoError(t, err)
	require.True(t, called)

	assert.ElementsMatch(t, []customfields.Field{
		{Key: "repository_id", Value: "42", Tag: true},
		{Key: "organization_id", Value: "7", Tag: true},
	}, customfields.Fields(ctx))
}
