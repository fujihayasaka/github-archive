package webhook

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/utils/ghtenant"
)

func Test_WebhookJob_EnqueuedAtTime(t *testing.T) {
	// Sample taken from running aqueduct locally, hopefully prod works the same
	// It looks like we're getting a time in milliseconds vs go's standard seconds or nanoseconds
	j := Job{EnqueuedAt: 1597092581001}
	require.Equal(t, "Mon Aug 10 20:49:41 UTC 2020", j.EnqueuedAtTime().UTC().Format(time.UnixDate))
}

func Test_WebhookJob_GitHubTenant_Unmarshal(t *testing.T) {
	// example of an incoming aqueduct JSON message with headers included
	// as webhook metadata
	hookJSON := `
	{
		"event": "foo",
		"hook": {
			"headers": [
				{"X-GitHub-Tenant": "foo-co"},
				{"X-GitHub-Tenant-ID": "1"}
			]
		}
	}
	`
	var j Job
	err := json.Unmarshal([]byte(hookJSON), &j)

	r := require.New(t)
	r.NoError(err)

	gt, err := j.GitHubTenant(true)
	r.NoError(err)
	r.Equal(gt.ID, int64(1))
	r.Equal(gt.Slug, "foo-co")
}

func Test_WebhookJob_GitHubTenant(t *testing.T) {
	tenantID := "1"
	tenantSlug := "foo"

	expectedTenantID := int64(1)
	expectedSlug := tenantSlug

	tests := []struct {
		name                 string
		headers              []header
		isMultiTenant        bool
		shouldErr            bool
		expectedGitHubTenant ghtenant.GitHubTenant
	}{
		{
			name: "no headers",
		},
		{
			name: "no-op-when-not-multi-tenant",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantIDHeader: "1",
				},
				map[string]string{
					ghtenant.GitHubTenantHeader: "foo",
				},
			},
		},
		{
			name: "multi-tenant/tenant-id-and-slug",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantIDHeader: tenantID,
				},
				map[string]string{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
			},
			isMultiTenant: true,
			expectedGitHubTenant: ghtenant.GitHubTenant{
				ID:   expectedTenantID,
				Slug: expectedSlug,
			},
		},
		{
			name:          "multi-tenant/no-headers",
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/empty-headers",
			isMultiTenant: true,
			headers:       []header{},
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/no-tenant-headers",
			isMultiTenant: true,
			headers: []header{
				map[string]string{
					"foo": "bar",
				},
			},
			shouldErr: true,
		},
		{
			name: "multi-tenant/tenant-id-only",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantIDHeader: tenantID,
				},
			},
			isMultiTenant: true,
			expectedGitHubTenant: ghtenant.GitHubTenant{
				ID: expectedTenantID,
			},
			shouldErr: true,
		},
		{
			name: "multi-tenant/tenant-slug-only",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
			},
			isMultiTenant: true,
			expectedGitHubTenant: ghtenant.GitHubTenant{
				Slug: expectedSlug,
			},
			shouldErr: true,
		},
		{
			name: "multi-tenant/tenant-id-malformed",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantIDHeader: "boom",
				},
				map[string]string{
					ghtenant.GitHubTenantHeader: tenantSlug,
				},
			},
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name: "multi-tenant/tenant-slug-is-empty",
			headers: []header{
				map[string]string{
					ghtenant.GitHubTenantIDHeader: tenantID,
				},
				map[string]string{
					ghtenant.GitHubTenantHeader: "",
				},
			},
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/empty-headers",
			headers:       []header{},
			isMultiTenant: true,
			shouldErr:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			j := Job{
				WebhookMetadata: &metadata{
					Headers: tt.headers,
				},
			}

			tenant, err := j.GitHubTenant(tt.isMultiTenant)
			if tt.shouldErr {
				require.Error(t, err)
				return
			}

			require.NoError(t, err)
			require.Equal(t, tt.expectedGitHubTenant, tenant)
		})
	}
}
