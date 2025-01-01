package utils_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/utils"
)

const (
	apiHost          = "https://api.github.com"
	apiPath          = "/api"
	graphqlPath      = "/graphql"
	githubServerHost = "https://github.com"

	apiWithPath     = "https://api.github.com/api"
	graphQLWithPath = "https://api.github.com/graphql"

	tenantSubdomain = "staff-01"

	tenantAPIHost         = "https://api.staff-01.github.com"
	tenantAPIWithPath     = "https://api.staff-01.github.com/api"
	tenantGraphQLWithPath = "https://api.staff-01.github.com/graphql"
	tenantGitHubServerURL = "https://staff-01.github.com"
)

func Test_URLProviderFactory(t *testing.T) {
	tests := []struct {
		name                    string
		host                    string
		apiPath                 string
		graphqlPath             string
		githubServerHost        string
		isMultiTenant           bool
		shouldCreateFactory     bool
		providerSubdomain       string
		shouldCreateProvider    bool
		expectedAPIURL          string
		expectedGraphQLURL      string
		expectedGitHubServerURL string
	}{
		{
			name:                    "dotcom/all_fields_set",
			host:                    apiHost,
			apiPath:                 apiPath,
			graphqlPath:             graphqlPath,
			githubServerHost:        githubServerHost,
			shouldCreateFactory:     true,
			shouldCreateProvider:    true,
			expectedAPIURL:          apiWithPath,
			expectedGraphQLURL:      graphQLWithPath,
			expectedGitHubServerURL: githubServerHost,
		},
		{
			name:                "dotcom/no_api_host",
			host:                "",
			apiPath:             apiPath,
			graphqlPath:         graphqlPath,
			githubServerHost:    githubServerHost,
			shouldCreateFactory: false,
		},
		{
			name:                    "dotcom/no_api_path",
			host:                    apiHost,
			apiPath:                 "",
			graphqlPath:             graphqlPath,
			githubServerHost:        githubServerHost,
			shouldCreateFactory:     true,
			shouldCreateProvider:    true,
			expectedAPIURL:          apiHost,
			expectedGraphQLURL:      graphQLWithPath,
			expectedGitHubServerURL: githubServerHost,
		},
		{
			name:                    "dotcom/no_graphql_path",
			host:                    apiHost,
			apiPath:                 apiPath,
			graphqlPath:             "",
			githubServerHost:        githubServerHost,
			shouldCreateFactory:     true,
			shouldCreateProvider:    true,
			expectedAPIURL:          apiWithPath,
			expectedGraphQLURL:      apiHost,
			expectedGitHubServerURL: githubServerHost,
		},
		{
			name:                "dotcom/no_github_server_host",
			host:                apiHost,
			apiPath:             apiPath,
			graphqlPath:         graphqlPath,
			githubServerHost:    "",
			shouldCreateFactory: false,
		},
		{
			name:                    "dotcom/set_provider_subdomain_no_ops",
			host:                    apiHost,
			apiPath:                 apiPath,
			graphqlPath:             graphqlPath,
			githubServerHost:        githubServerHost,
			shouldCreateFactory:     true,
			providerSubdomain:       tenantSubdomain,
			shouldCreateProvider:    true,
			expectedAPIURL:          apiWithPath,
			expectedGraphQLURL:      graphQLWithPath,
			expectedGitHubServerURL: githubServerHost,
		},
		{
			name:                "dotcom/no_api_host_scheme",
			host:                "api.github.com",
			apiPath:             apiPath,
			graphqlPath:         graphqlPath,
			githubServerHost:    githubServerHost,
			shouldCreateFactory: false,
		},
		{
			name:                "dotcom/no_github_server_scheme",
			host:                apiHost,
			apiPath:             apiPath,
			graphqlPath:         graphqlPath,
			githubServerHost:    "github.com",
			shouldCreateFactory: false,
		},
		{
			name:                    "multi-tenant/provider_subdomain_set",
			host:                    apiHost,
			apiPath:                 apiPath,
			graphqlPath:             graphqlPath,
			githubServerHost:        githubServerHost,
			isMultiTenant:           true,
			shouldCreateFactory:     true,
			providerSubdomain:       tenantSubdomain,
			shouldCreateProvider:    true,
			expectedAPIURL:          tenantAPIWithPath,
			expectedGraphQLURL:      tenantGraphQLWithPath,
			expectedGitHubServerURL: tenantGitHubServerURL,
		},
		{
			name:                 "multi-tenant/provider_subdomain_not_set",
			host:                 apiHost,
			apiPath:              apiPath,
			graphqlPath:          graphqlPath,
			githubServerHost:     githubServerHost,
			isMultiTenant:        true,
			shouldCreateFactory:  true,
			shouldCreateProvider: false,
		},
		{
			name:                    "multi-tenant/host_contains_subdomain",
			host:                    "https://api.staff-01.github.com",
			apiPath:                 apiPath,
			graphqlPath:             graphqlPath,
			githubServerHost:        "https://staff-01.github.com",
			isMultiTenant:           true,
			shouldCreateFactory:     true,
			providerSubdomain:       "staff-02",
			shouldCreateProvider:    true,
			expectedAPIURL:          "https://api.staff-02.github.com/api",
			expectedGraphQLURL:      "https://api.staff-02.github.com/graphql",
			expectedGitHubServerURL: "https://staff-02.github.com",
		},
		{
			name:                    "multi-tenant/host_contains_tenant_placeholder",
			host:                    "https://api.<tenant-subdomain>.github.com",
			apiPath:                 apiPath,
			graphqlPath:             graphqlPath,
			githubServerHost:        "https://<tenant-subdomain>.github.com",
			isMultiTenant:           true,
			shouldCreateFactory:     true,
			providerSubdomain:       "staff-02",
			shouldCreateProvider:    true,
			expectedAPIURL:          "https://api.staff-02.github.com/api",
			expectedGraphQLURL:      "https://api.staff-02.github.com/graphql",
			expectedGitHubServerURL: "https://staff-02.github.com",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := require.New(t)

			f, err := utils.NewURLProviderFactory(tt.host, tt.apiPath, tt.graphqlPath, tt.githubServerHost, tt.isMultiTenant)

			if tt.shouldCreateFactory {
				r.NoError(err)
				r.NotNil(f)
			} else {
				r.Error(err)
				r.Nil(f)
				return
			}

			p, err := f.NewProvider(tt.providerSubdomain)

			if tt.shouldCreateProvider {
				r.NoError(err)
				r.NotNil(p)

				r.Equal(tt.expectedAPIURL, p.V3ApiURL())
				r.Equal(tt.expectedGraphQLURL, p.GraphQLApiURL())
				r.Equal(tt.expectedGitHubServerURL, p.GitHubServerURL())
			} else {
				r.Error(err)
				r.Nil(p)
			}
		})
	}
}

func Test_GraphQLProvider(t *testing.T) {
	host := "https://api.github.com"
	graphqlPath := "/graphql"
	hostWithPath := "https://api.github.com/graphql"

	tests := []struct {
		name        string
		host        string
		path        string
		shouldErr   bool
		expectedURL string
	}{
		{
			name:      "no_host",
			host:      "",
			path:      graphqlPath,
			shouldErr: true,
		},
		{
			name:      "malformed_host",
			host:      "http:/github.com",
			path:      graphqlPath,
			shouldErr: true,
		},
		{
			name:        "host_missing_trailing_slash",
			host:        "https://api.github.com",
			path:        graphqlPath,
			expectedURL: hostWithPath,
		},
		{
			name:        "no_path",
			host:        host,
			expectedURL: host,
		},
		{
			name:        "path_missing_slash",
			host:        host,
			path:        "graphql",
			shouldErr:   false,
			expectedURL: hostWithPath,
		},
		{
			name:        "host_and_path_set",
			host:        host,
			path:        graphqlPath,
			expectedURL: hostWithPath,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := require.New(t)

			p, err := utils.NewGraphQLURLProvider(tt.host, tt.path)

			if tt.shouldErr {
				r.Error(err)
				r.Nil(p)
				return
			}

			r.NoError(err)
			r.NotNil(p)
			r.Equal(tt.expectedURL, p.GraphQLApiURL())
		})
	}
}

func Test_FormatTenantURL(t *testing.T) {
	type out struct {
		url string
		err error
	}

	cases := []struct {
		name     string
		host     string
		slug     string
		expected out
	}{
		{
			name:     "empty",
			host:     "",
			slug:     "",
			expected: out{"", nil},
		},
		{
			name:     "no slug/normal host",
			host:     "https://results-receiver.actions.ghe.com/",
			slug:     "",
			expected: out{"https://results-receiver.actions.ghe.com/", nil},
		},
		{
			name:     "no slug/tenant host",
			host:     "https://results-receiver.<tenant>.actions.ghe.com/",
			slug:     "",
			expected: out{"", utils.ErrEmptySlug},
		},
		{
			name:     "slug/normal host",
			host:     "https://results-receiver.actions.ghe.com/",
			slug:     "staffship-01",
			expected: out{"https://results-receiver.actions.ghe.com/", nil},
		},
		{
			name:     "slug/tenant host",
			host:     "https://results-receiver.<tenant>.actions.ghe.com/",
			slug:     "staffship-01",
			expected: out{"https://results-receiver.staffship-01.actions.ghe.com/", nil},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := require.New(t)

			url, err := utils.FormatTenantURL(tc.host, tc.slug)

			r.Equal(tc.expected.url, url)
			r.Equal(tc.expected.err, err)
		})
	}
}
