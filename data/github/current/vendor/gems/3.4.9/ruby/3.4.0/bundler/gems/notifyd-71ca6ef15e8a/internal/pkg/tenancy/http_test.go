package tenancy

import (
	"context"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
)

type mockClient struct {
}

func (m *mockClient) Do(_ *http.Request) (*http.Response, error) {
	return nil, nil
}

func Test_HTTP_IntoHeaders(t *testing.T) {
	tenant := tenantFixture(t)

	headers := IntoHeadersMap(tenant)

	require.Equal(t, "avocado", headers[HeaderTenantSlug])
	require.Equal(t, "123", headers[HeaderTenantID])
}

func Test_HTTP_Inject(t *testing.T) {
	tenant := tenantFixture(t)
	headers := make(map[string]string)

	Inject(tenant, headers)

	require.Equal(t, "avocado", headers[HeaderTenantSlug])
	require.Equal(t, "123", headers[HeaderTenantID])
}

func Test_HTTP_UpdateFromMap(t *testing.T) {
	tenant := tenantFixture(t)
	headers := map[string]string{
		HeaderTenantSlug: "lemon",
		HeaderTenantID:   "456",
	}

	var err error
	tenant, err = UpdateFromMap(tenant, headers)
	require.NoError(t, err)
	require.Equal(t, "lemon", tenant.Slug())
	require.Equal(t, int64(456), tenant.ID())
}

func Test_HTTP_UpdateFromMap_IndifferentCase(t *testing.T) {
	tenant := tenantFixture(t)
	headers := map[string]string{
		"x-github-Tenant": "lemon",
		HeaderTenantID:    "456",
	}

	var err error
	tenant, err = UpdateFromMap(tenant, headers)
	require.NoError(t, err)
	require.Equal(t, "lemon", tenant.Slug())
	require.Equal(t, int64(456), tenant.ID())
}

func Test_HTTP_UpdateFromMap_Errors(t *testing.T) {
	tenant := tenantFixture(t)
	headers := map[string]string{
		HeaderTenantSlug: "lemon",
	}

	var err error
	tenant, err = UpdateFromMap(tenant, headers)
	require.Error(t, err)
	require.Equal(t, "lemon", tenant.Slug())
}

func Test_HTTP_UpdateFromHeaders(t *testing.T) {
	tenant := tenantFixture(t)
	headers := http.Header{}
	headers.Add(HeaderTenantSlug, "lemon")
	headers.Add(HeaderTenantID, "456")

	var err error
	tenant, err = UpdateFromHeaders(tenant, headers)
	require.NoError(t, err)
	require.Equal(t, "lemon", tenant.Slug())
	require.Equal(t, int64(456), tenant.ID())
}

func Test_HTTP_UpdateFromHeaders_IndifferentCase(t *testing.T) {
	tenant := tenantFixture(t)
	headers := http.Header{}
	headers.Add("x-github-TENANT", "lemon")
	headers.Add(HeaderTenantID, "456")

	var err error
	tenant, err = UpdateFromHeaders(tenant, headers)
	require.NoError(t, err)
	require.Equal(t, "lemon", tenant.Slug())
	require.Equal(t, int64(456), tenant.ID())
}

func Test_HTTP_UpdateFromHeaders_Errors(t *testing.T) {
	tenant := tenantFixture(t)
	headers := http.Header{}
	headers.Add(HeaderTenantSlug, "lemon")

	var err error
	tenant, err = UpdateFromHeaders(tenant, headers)
	require.Error(t, err)
	require.Equal(t, "lemon", tenant.Slug())
}

func Test_HTTP_Forwarder(t *testing.T) {
	tenant := tenantFixture(t)

	client := &mockClient{}
	forwarder := NewForwarder(client)

	req, err := http.NewRequest(http.MethodGet, "http://example.com", http.NoBody)
	req = req.WithContext(ContextWithTenant(context.Background(), tenant))

	require.NoError(t, err)
	require.Empty(t, req.Header.Get(HeaderTenantSlug))
	require.Empty(t, req.Header.Get(HeaderTenantID))

	resp, err := forwarder.Do(req) //nolint:bodyclose // resp is nil
	require.NoError(t, err)
	require.Nil(t, resp)
	require.Equal(t, "avocado", req.Header.Get(HeaderTenantSlug))
	require.Equal(t, "123", req.Header.Get(HeaderTenantID))
}

func Test_HTTP_Forwarder_WithoutTenant(t *testing.T) {
	client := &mockClient{}
	forwarder := NewForwarder(client)

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, "http://example.com", http.NoBody)
	require.NoError(t, err)

	resp, err := forwarder.Do(req) //nolint:bodyclose // resp is nil
	require.Error(t, err)
	require.Nil(t, resp)
}

func tenantFixture(t *testing.T) Tenant {
	t.Helper()

	tenant := NewMultiTenant()
	tenant = tenant.WithSlug("avocado")
	tenant = tenant.WithID(123)

	return tenant
}
