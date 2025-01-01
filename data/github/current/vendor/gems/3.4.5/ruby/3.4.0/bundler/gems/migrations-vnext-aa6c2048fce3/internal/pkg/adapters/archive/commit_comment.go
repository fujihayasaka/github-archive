package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// CommitComment represents a commit comment in a GitHub repository
type CommitComment struct {
	URL       string    `json:"url"`
	User      string    `json:"user"`
	Body      string    `json:"body"`
	Path      string    `json:"path"`
	Position  int64     `json:"position"`
	CreatedAt time.Time `json:"created_at"`
}

// ToV1CommitComment converts an archive CommitComment to a v1.CommitComment
func (r *CommitComment) ToV1CommitComment() (*v1.CommitComment, error) {
	return &v1.CommitComment{
		ResourceId:     r.URL,
		UserResourceId: r.User,
		Body:           r.Body,
		Path:           r.Path,
		Position:       r.Position,
		CreatedAt:      toTimestamp(r.CreatedAt),
	}, nil
}
