// Package github is a wrapper around the open-source google/go-github
// package that implements additional functionality.
package github

import (
	"context"
	"fmt"
	"net/http"
	"net/http/cookiejar"

	"github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
	"golang.org/x/net/publicsuffix"
	"golang.org/x/oauth2"
)

// Client is a struct which uses the interfaces declared above as struct fields.
// These fields match those exposed by the (*github.Client) struct. This struct
// can be used by the real client or by mocks. There are some extra fields which
// are explained within the struct.
type Client struct {
	// restClient is the wrapped *github.Client. We embed it so that we can reference
	// certain internals.
	restClient *github.Client

	Issues                  IssuesService
	PullRequests            PullRequestsService
	PullRequestReviewThread PullRequestGraphQLAugmentService
	Repositories            RepositoriesService
	StaffTools              StaffToolsService
	Reactions               ReactionsService
	CommitComments          CommitCommentsService
}

// New creates a new client. It first creates a (*github.Client) using
// the provided information then wraps it in our own Client type.
func New(baseURL, uploadURL, token string) (*Client, error) {
	// A cookie jar is needed if performing operations which require
	// authentication through the web UI.
	cookieJar, err := cookiejar.New(&cookiejar.Options{PublicSuffixList: publicsuffix.List})
	if err != nil {
		return nil, fmt.Errorf("error creating restClient: failed to create the cookie jar: %w", err)
	}

	// Create a REST HTTP client
	restHTTPClient := &http.Client{}
	restHTTPClient.Jar = cookieJar

	restClient, err := github.NewClient(restHTTPClient).WithEnterpriseURLs(baseURL, uploadURL)
	if err != nil {
		return nil, fmt.Errorf("error creating restClient: %w", err)
	}

	if token != "" {
		restClient = restClient.WithAuthToken(token)
	}

	// Create GraphQL client
	src := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	graphqlClient := githubv4.NewEnterpriseClient(baseURL+"/api/graphql", oauth2.NewClient(context.Background(), src))

	return &Client{
		restClient:              restClient,
		Issues:                  restClient.Issues,
		PullRequests:            restClient.PullRequests,
		PullRequestReviewThread: &PullRequestThreadServiceImpl{client: graphqlClient},
		Repositories:            restClient.Repositories,
		StaffTools:              &staffToolsServiceImpl{client: restClient},
		Reactions:               restClient.Reactions,
		// client.Repositories satisfies the CommitCommentsService interface.
		CommitComments: restClient.Repositories,
	}, nil
}

// HTTPClient returns the underlying HTTP client that is used by the
// GitHub client. This is useful when needing to perform requests against
// the UI.
func (c *Client) HTTPClient() *http.Client {
	return c.restClient.Client()
}
