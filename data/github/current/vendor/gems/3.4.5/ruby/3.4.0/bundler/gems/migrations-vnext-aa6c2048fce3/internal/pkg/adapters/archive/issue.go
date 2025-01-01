// Package archive contains the domain logic to load resources from a migrations archive into Kafka
package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// Issue represents an issue in a GitHub repository
type Issue struct {
	Assignee   string    `json:"assignee"`
	Assignees  []string  `json:"assignees"`
	Body       string    `json:"body"`
	ClosedAt   time.Time `json:"closed_at"`
	CreatedAt  time.Time `json:"created_at"`
	Labels     []string  `json:"labels"`
	Milestone  string    `json:"milestone"`
	Reactions  Reactions `json:"reactions"`
	Repository string    `json:"repository"`
	Title      string    `json:"title"`
	Type       string    `json:"type"`
	URL        string    `json:"url"`
	UpdatedAt  time.Time `json:"updated_at"`
	User       string    `json:"user"`
}

// ToV1Issue converts an archive Issue to a v1.Issue
func (r *Issue) ToV1Issue() (*v1.Issue, error) {
	return &v1.Issue{
		ResourceId:           r.URL,
		UserResourceId:       r.User,
		Title:                r.Title,
		Body:                 r.Body,
		AssigneesResourceIds: addDedup(r.Assignees, r.Assignee),
		CreatedAt:            toTimestamp(r.CreatedAt),
		ClosedAt:             toTimestamp(r.ClosedAt),
		UpdatedAt:            toTimestamp(r.UpdatedAt),
	}, nil
}
