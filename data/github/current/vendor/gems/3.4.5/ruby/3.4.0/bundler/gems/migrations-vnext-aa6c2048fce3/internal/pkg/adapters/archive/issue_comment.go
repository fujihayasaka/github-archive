package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// IssueComment represents an issue comment in a GitHub repository
type IssueComment struct {
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
	Formatter string    `json:"formatter"`
	Issue     string    `json:"issue"`
	Reactions Reactions `json:"reactions"`
	Type      string    `json:"type"`
	URL       string    `json:"url"`
	User      string    `json:"user"`
}

// ToV1IssueComment converts an archive IssueComment to a v1.IssueComment
func (r *IssueComment) ToV1IssueComment() (*v1.IssueComment, error) {
	return &v1.IssueComment{
		ResourceId:     r.URL,
		UserResourceId: r.User,
		Body:           r.Body,
		CreatedAt:      toTimestamp(r.CreatedAt),
	}, nil
}
