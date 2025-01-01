package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// Milestone represents a milestone in a repository.
type Milestone struct {
	Type        string    `json:"type"`
	URL         string    `json:"url"`
	Repository  string    `json:"repository"`
	User        string    `json:"user"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	State       string    `json:"state"`
	DueOn       time.Time `json:"due_on"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	ClosedAt    time.Time `json:"closed_at,omitempty"`
}

// Milestones represents a slice of milestones.
type Milestones []Milestone

// ToV1Milestones converts a slice of archive Milestones to v1.Milestones
func (ms *Milestones) ToV1Milestones(milestoneToIssues map[string][]string) ([]*v1.Milestone, error) {
	var v1Milestones []*v1.Milestone
	for _, milestone := range *ms {
		v1Milestone, err := milestone.ToV1Milestone(milestoneToIssues)
		if err != nil {
			return nil, err
		}
		v1Milestones = append(v1Milestones, v1Milestone)
	}
	return v1Milestones, nil
}

// ToV1Milestone converts an archive Milestone to a v1.Milestone
func (m *Milestone) ToV1Milestone(milestoneToIssues map[string][]string) (*v1.Milestone, error) {
	return &v1.Milestone{
		ResourceId:       m.URL,
		Title:            m.Title,
		UserResourceId:   m.User,
		Description:      m.Description,
		State:            m.State,
		DueOn:            toTimestamp(m.DueOn),
		CreatedAt:        toTimestamp(m.CreatedAt),
		UpdatedAt:        toTimestamp(m.UpdatedAt),
		ClosedAt:         toTimestamp(m.ClosedAt),
		IssueResourceIds: milestoneToIssues[m.URL],
	}, nil
}
