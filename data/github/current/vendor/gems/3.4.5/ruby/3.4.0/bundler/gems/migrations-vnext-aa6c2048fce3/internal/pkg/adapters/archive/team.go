package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	// TeamMember represents individual team members
	TeamMember struct {
		User string `json:"user"`
		Role string `json:"role"`
	}

	// TeamPermissions represents the permissions of the team
	TeamPermissions struct {
		User string `json:"user"`
		Role string `json:"role"`
	}

	// Team represents the main team structure
	Team struct {
		Type         string            `json:"type"`
		URL          string            `json:"url"`
		Organization string            `json:"organization"`
		ParentTeam   string            `json:"parent_team"`
		Name         string            `json:"name"`
		Description  string            `json:"description"`
		Privacy      string            `json:"privacy"`
		Permissions  []TeamPermissions `json:"permissions"`
		TeamMembers  []TeamMember      `json:"members"`    // Slice of TeamMember structs for team members
		CreatedAt    time.Time         `json:"created_at"` // Time type for the timestamp
	}
)

// ToV1Team converts a Team to a v1.Team.
func (t *Team) ToV1Team() (*v1.Team, error) {
	return &v1.Team{
		ResourceId:           t.URL,
		ParentTeamResourceId: t.ParentTeam,
		Name:                 t.Name,
		Visibility:           t.Privacy,
	}, nil
}
