package sweagentd

import "net/url"

// GitHubAPI defines the interface for accessing GitHub API configuration.
type GitHubAPI interface {
	BaseURL() *url.URL
}
