package archive

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// Attachment represents an attach in a GitHub repository.
type Attachment struct {
	Type             string    `json:"type"`
	URL              string    `json:"url"`
	User             string    `json:"user"`
	AssetName        string    `json:"asset_name"`
	AssetContentType string    `json:"asset_content_type"`
	AssetURL         string    `json:"asset_url"`
	CreatedAt        time.Time `json:"created_at"`
	// One of the following will be set.
	Issue              string `json:"issue,omitempty"`
	IssueComment       string `json:"issue_comment,omitempty"`
	PullRequest        string `json:"pull_request,omitempty"`
	PullRequestComment string `json:"pull_request_review_comment,omitempty"`
	PullRequestReview  string `json:"pull_request_review,omitempty"`
	CommitComment      string `json:"commit_comment,omitempty"`
	Discussion         string `json:"discussion,omitempty"`
	DiscussionComment  string `json:"discussion_comment,omitempty"`
}

// Attachments contains a collection of Attachment.
type Attachments []Attachment

// ToV1Attachment converts an archive attachment to a v1.Attachment
func (r *Attachment) ToV1Attachment() (*v1.Attachment, error) {
	resource := r.extractResource()
	repositoryID, err := r.extractRepositoryResourceID()
	if err != nil {
		return nil, fmt.Errorf("could not extract repository id for attachment: %w", err)
	}
	return &v1.Attachment{
		Type:                 r.Type,
		ResourceId:           r.URL,
		RepositoryId:         repositoryID,
		Name:                 r.AssetName,
		ContentType:          r.AssetContentType,
		UserResourceId:       r.User,
		AssetUrl:             r.AssetURL,
		ReferencedByResource: resource,
	}, nil
}

// extractResource is a helper that untangles a set of oneof properties.
func (r *Attachment) extractResource() string {
	resource := ""
	switch {
	case r.Issue != "":
		resource = r.Issue
	case r.IssueComment != "":
		resource = r.IssueComment
	case r.PullRequest != "":
		resource = r.PullRequest
	case r.PullRequestComment != "":
		resource = r.PullRequestComment
	case r.PullRequestReview != "":
		resource = r.PullRequestReview
	case r.CommitComment != "":
		resource = r.CommitComment
	case r.Discussion != "":
		resource = r.Discussion
	case r.DiscussionComment != "":
		resource = r.DiscussionComment
	}

	return resource
}

// Infers the repository based on the resource this attachment is referenced by.
func (r *Attachment) extractRepositoryResourceID() (string, error) {
	resource := r.extractResource()
	// Parse the URL
	parsedURL, err := url.Parse(resource)
	if err != nil {
		return "", fmt.Errorf("could not parse resource URL: %w", err)
	}

	// Split the path of the URL (e.g., "/acme/widgets/...")
	pathSegments := strings.Split(parsedURL.Path, "/")

	// Ensure we have at least the repo owner and repo name in the path
	if len(pathSegments) < 3 {
		return "", fmt.Errorf("invalid URL: %s", resource)
	}

	// Construct the base URL in the format "http://github.dev/acme/widgets/"
	repoBaseURL := fmt.Sprintf("%s://%s/%s/%s", parsedURL.Scheme, parsedURL.Host, pathSegments[1], pathSegments[2])

	return repoBaseURL, nil
}
