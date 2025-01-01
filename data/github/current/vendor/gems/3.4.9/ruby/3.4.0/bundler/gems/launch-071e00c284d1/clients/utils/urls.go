package utils

import (
	"errors"
	"fmt"
	"net/url"
	"path"
	"strings"
)

var (
	ErrEmptySlug = errors.New("empty slug for multitenant url")
)

// GraphQLProvider is responsible for creating URLs for the GraphQL client
type GraphQLURLProvider interface {
	GraphQLApiURL() string
}

type graphqlURLProvider struct {
	url  *url.URL
	path string
}

func (g *graphqlURLProvider) GraphQLApiURL() string {
	return g.url.String()
}

func NewGraphQLURLProvider(host string, graphqlPath string) (GraphQLURLProvider, error) {
	if host == "" {
		return nil, fmt.Errorf("host cannot be empty")
	}

	u, err := parseRawURL(host)
	if err != nil {
		return nil, fmt.Errorf("error parsing host '%s' to a URL: %w", host, err)
	}

	u.Path = path.Join(u.Path, graphqlPath)

	return &graphqlURLProvider{
		url:  u,
		path: graphqlPath,
	}, nil
}

// URLProviderFactory is responsible for creating URLProviders
type URLProviderFactory interface {
	// NewProvider will create a new URLProvider with the given tenant subdomain
	// If the factory is not multi-tenant, the tenant subdomain will be ignored
	NewProvider(tenantSubdomain string) (URLProvider, error)
}

// URLProvider is responsible for generating various GitHub URLs
type URLProvider interface {
	V3ApiURL() string
	GitHubServerURL() string
	GraphQLURLProvider
}

type urlProviderFactory struct {
	publicAPIURL  *url.URL
	serverURL     *url.URL
	v3ApiPath     string
	graphqlPath   string
	isMultiTenant bool
}

func (upf *urlProviderFactory) NewProvider(subdomain string) (URLProvider, error) {
	if !upf.isMultiTenant {
		return &urlProvider{
			publicAPIURL: upf.publicAPIURL,
			serverURL:    upf.serverURL,
			v3ApiPath:    upf.v3ApiPath,
			graphqlPath:  upf.graphqlPath,
		}, nil
	}

	if subdomain == "" {
		return nil, errors.New("tenant subdomain can not be empty")
	}

	publicAPIURL, err := newAPIURLWithTenantSubdomain(upf.publicAPIURL, subdomain)
	if err != nil {
		return nil, fmt.Errorf("error creating externalAPIURL for github tenant: %w", err)
	}

	serverURL, err := newGitHubURLWithTenantSubdomain(upf.serverURL, subdomain)
	if err != nil {
		return nil, fmt.Errorf("error creating externalGitHubURL for github tenant: %w", err)
	}

	return &urlProvider{
		publicAPIURL: publicAPIURL,
		serverURL:    serverURL,
		v3ApiPath:    upf.v3ApiPath,
		graphqlPath:  upf.graphqlPath,
	}, nil

}

func NewURLProviderFactory(externalAPIHost string, v3ApiPath string, graphqlPath string, externalGitHubHost string, isMultiTenant bool) (URLProviderFactory, error) {
	if externalAPIHost == "" {
		return nil, fmt.Errorf("host cannot be empty")
	}

	publicAPIURL, err := parseRawURL(externalAPIHost)
	if err != nil {
		return nil, fmt.Errorf("error parsing externalAPIHost '%s' to a URL: %w", externalAPIHost, err)
	}

	serverURL, err := parseRawURL(externalGitHubHost)
	if err != nil {
		return nil, fmt.Errorf("error parsing externalGitHubHost '%s' to a URL: %w", externalGitHubHost, err)
	}

	return &urlProviderFactory{
		publicAPIURL:  publicAPIURL,
		serverURL:     serverURL,
		v3ApiPath:     v3ApiPath,
		graphqlPath:   graphqlPath,
		isMultiTenant: isMultiTenant,
	}, nil
}

type urlProvider struct {
	publicAPIURL *url.URL
	serverURL    *url.URL
	v3ApiPath    string
	graphqlPath  string
}

func (up *urlProvider) V3ApiURL() string {
	u2 := *up.publicAPIURL
	u2.Path = path.Join(u2.Path, up.v3ApiPath)
	return u2.String()
}

func (up *urlProvider) GraphQLApiURL() string {
	u2 := *up.publicAPIURL
	u2.Path = path.Join(u2.Path, up.graphqlPath)
	return u2.String()
}

func (up *urlProvider) GitHubServerURL() string {
	return up.serverURL.String()
}

func newAPIURLWithTenantSubdomain(u *url.URL, subdomain string) (*url.URL, error) {
	urlParts := make([]string, 0, 4)

	// split the hostname into the top-level domain and the subdomain
	// e.g. api.github.com becomes [api, github.com]
	parts := strings.SplitN(u.Hostname(), ".", 2)
	if len(parts) != 2 {
		return nil, errors.New("error creating URL with tenant subdomain. could not parse subdomain from domain")
	}

	urlParts = append(urlParts, parts[0])

	// There are two cases here:
	// 1. The top-level domain has 3 parts (e.g. staff-01.ghe.com or <tenant-subdomain>.ghe.com)
	// 2. The top-level domain has 2 parts (e.g. ghe.com)
	// In the first case, we need to replace the first part of the top-level domain with the tenant subdomain
	// In the second case, we need to append the tenant subdomain to the top-level domain
	topLevelDomainParts := strings.SplitN(parts[1], ".", 3)
	if len(topLevelDomainParts) == 3 {
		topLevelDomainParts[0] = subdomain
		urlParts = append(urlParts, topLevelDomainParts...)
	} else {
		urlParts = append(urlParts, subdomain)
		urlParts = append(urlParts, topLevelDomainParts...)
	}

	// at the end of this process, we should have 4 tokens in the urlParts slice
	// e.g. [api, <tenant-subdomain>, github, com]
	if len(urlParts) != 4 {
		return nil, errors.New("error creating URL with tenant subdomain. could not parse subomain from domain")
	}

	// reconstruct the url so that the tenant subdomain becomes the second-level domain
	// ex: http://api.ghe.com becomes http://api.<tenant-subdomain>.ghe.com
	hostNameWithTenant := fmt.Sprintf("%s://%s", u.Scheme, strings.Join(urlParts, "."))

	urlWithTenantSubdomain, err := url.Parse(hostNameWithTenant)
	if err != nil {
		return nil, err
	}

	return urlWithTenantSubdomain, nil
}

func newGitHubURLWithTenantSubdomain(u *url.URL, subdomain string) (*url.URL, error) {
	urlParts := make([]string, 0, 3)
	parts := strings.SplitN(u.Hostname(), ".", 3)

	// There are two cases tha are supported:
	// 1. ghe.com
	// 2. <tenant-subdomain>.ghe.com
	// In the first case, we need to add the tenant subdomain as the second-level domain
	// In the second case, we need to replace the second-level domain with the tenant subdomain
	switch len(parts) {
	case 2:
		urlParts = append(urlParts, subdomain)
		urlParts = append(urlParts, parts[0])
		urlParts = append(urlParts, parts[1])
	case 3:
		urlParts = append(urlParts, subdomain)
		urlParts = append(urlParts, parts[1])
		urlParts = append(urlParts, parts[2])
	default:
		return nil, errors.New("error creating URL with tenant subdomain. could not parse subomain from domain")
	}

	hostNameWithTenant := fmt.Sprintf("%s://%s", u.Scheme, strings.Join(urlParts, "."))

	urlWithTenantSubdomain, err := url.Parse(hostNameWithTenant)
	if err != nil {
		return nil, err
	}

	return urlWithTenantSubdomain, nil
}

func parseRawURL(rawURL string) (*url.URL, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("error parsing '%s' to a URL: %w", rawURL, err)
	}

	// double check that the hostname is not an empty string. this can happen if the raw url
	// does not have slashes after the scheme.
	// See: https://pkg.go.dev/net/url
	//
	// this is a special case for urlProvider to generate urls at runtime with the GitHub tenant subdomain
	// when executing in multi-tenant environments
	if u.Hostname() == "" {
		return nil, fmt.Errorf("could not retrieve hostname for '%s', check for missing scheme", rawURL)
	}

	return u, nil
}

func TestURLProviderFactoryWithDefaults() (URLProviderFactory, error) {
	return NewURLProviderFactory("http://api.github.com", "", "/graphql", "http://github.com", false)
}

func TestGraphQLURLProviderWithDefaults() (GraphQLURLProvider, error) {
	p, err := NewGraphQLURLProvider("http://example.com", "/graphql")
	if err != nil {
		return nil, fmt.Errorf("error creating url provider factory: %w", err)
	}

	return p, nil
}

// FormatTenantURL replaces <tenant> in a url with the given slug.
func FormatTenantURL(url, slug string) (string, error) {
	directive := `<tenant>`
	if slug == "" {
		if strings.Contains(url, directive) {
			return "", ErrEmptySlug
		}
		return url, nil
	}
	return strings.ReplaceAll(url, directive, slug), nil
}
