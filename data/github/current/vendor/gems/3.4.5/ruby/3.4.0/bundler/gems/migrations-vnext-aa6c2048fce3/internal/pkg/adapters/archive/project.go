package archive

import (
	"fmt"
	"regexp"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// Project represents the main project object
type Project struct {
	URL        string    `json:"url"`
	Name       string    `json:"name"`
	Number     int64     `json:"number"`
	OwnerURL   string    `json:"owner"`
	CreatorURL string    `json:"creator"`
	Body       string    `json:"body"`
	IsPublic   bool      `json:"is_public"`
	Columns    []Column  `json:"columns"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	ClosedAt   time.Time `json:"closed_at"`
}

// Column represents a column in a project
type Column struct {
	Position  int64      `json:"position"`
	Name      string     `json:"name"`
	Color     string     `json:"color"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	HiddenAt  time.Time  `json:"hidden_at"`
	Purpose   string     `json:"purpose"`
	Cards     []Card     `json:"cards"`
	Workflows []Workflow `json:"workflows"`
}

// Card represents a card in a column
type Card struct {
	CreatorURL string    `json:"creator"`
	Content    string    `json:"content"`
	Note       string    `json:"note"`
	Priority   *uint64   `json:"priority"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	HiddenAt   time.Time `json:"hidden_at"`
	ArchivedAt time.Time `json:"archived_at"`
}

// Workflow represents a workflow in a column
type Workflow struct {
	Creator     string    `json:"creator"`
	LastUpdater string    `json:"last_updater"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	TriggerType string    `json:"trigger_type"`
	Actions     []Action  `json:"actions"`
}

// Action represents an action in a workflow
type Action struct {
	Creator     string    `json:"creator"`
	LastUpdater string    `json:"last_updater"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ToV1Project converts a Project to a v1.Project
func (p *Project) ToV1Project() *v1.Project {
	ownerType := p.extractOwnerType()

	return &v1.Project{
		ResourceId:        p.URL,
		Name:              p.Name,
		Number:            p.Number,
		OwnerResourceId:   p.OwnerURL,
		OwnerType:         ownerType,
		CreatorResourceId: p.CreatorURL,
		Body:              p.Body,
		IsPublic:          p.IsPublic,
		CreatedAt:         toTimestamp(p.CreatedAt),
		UpdatedAt:         toTimestamp(p.UpdatedAt),
		ClosedAt:          toTimestamp(p.ClosedAt),
	}
}

func (p *Project) extractV1ProjectColumns() []*v1.ProjectColumn {
	var columns []*v1.ProjectColumn

	for _, column := range p.Columns {
		var projectWorkflows []*v1.ProjectWorkflow
		for _, pw := range column.Workflows {
			var projectWorkflowActions []*v1.ProjectWorkflowAction
			for _, pwa := range pw.Actions {
				projectWorkflowActions = append(projectWorkflowActions, &v1.ProjectWorkflowAction{
					CreatorResourceId:     pwa.Creator,
					CreatedAt:             toTimestamp(pwa.CreatedAt),
					LastUpdaterResourceId: pwa.LastUpdater,
					UpdatedAt:             toTimestamp(pwa.UpdatedAt),
				})
			}
			projectWorkflows = append(projectWorkflows, &v1.ProjectWorkflow{
				CreatorResourceId:     pw.Creator,
				TriggerType:           pw.TriggerType,
				CreatedAt:             toTimestamp(pw.CreatedAt),
				LastUpdaterResourceId: pw.LastUpdater,
				UpdatedAt:             toTimestamp(pw.UpdatedAt),
				Actions:               projectWorkflowActions,
			})
		}
		columns = append(columns, &v1.ProjectColumn{
			ResourceId:        columnResourceID(p.URL, column.Position),
			Name:              column.Name,
			Color:             column.Color,
			CreatedAt:         toTimestamp(column.CreatedAt),
			UpdatedAt:         toTimestamp(column.UpdatedAt),
			Purpose:           column.Purpose,
			Position:          column.Position,
			HiddenAt:          toTimestamp(column.HiddenAt),
			ProjectResourceId: p.URL,
			Workflows:         projectWorkflows,
		})
	}

	return columns
}

func (p *Project) extractV1ProjectCardsBatches() []*v1.ProjectCardsBatch {
	var batches []*v1.ProjectCardsBatch

	for _, column := range p.Columns {
		var cards []*v1.ProjectCard
		for _, card := range column.Cards {
			var priority uint64
			if card.Priority != nil {
				priority = *card.Priority
			}
			cards = append(cards, &v1.ProjectCard{
				ResourceId:              fmt.Sprintf("project-card-%s", uuid.New().String()),
				CreatorResourceId:       card.CreatorURL,
				ContentResourceId:       card.Content,
				Note:                    card.Note,
				Priority:                wrapperspb.UInt64(priority),
				CreatedAt:               toTimestamp(card.CreatedAt),
				UpdatedAt:               toTimestamp(card.UpdatedAt),
				ArchivedAt:              toTimestamp(card.ArchivedAt),
				HiddenAt:                toTimestamp(card.HiddenAt),
				ProjectColumnResourceId: columnResourceID(p.URL, column.Position),
			})
		}
		batches = append(batches, &v1.ProjectCardsBatch{
			ResourceId:              fmt.Sprintf("project-cards-batch-%d-%s", column.Position, uuid.New().String()),
			ProjectColumnResourceId: columnResourceID(p.URL, column.Position),
			Cards:                   cards,
		})
	}

	return batches
}

func (p *Project) extractOwnerType() v1.OwnerType {
	orgRegex := regexp.MustCompile(`^https?://[^/]+/[^/]+/projects/\d+$`)
	userRegex := regexp.MustCompile(`^https?://[^/]+/users/[^/]+/projects/\d+$`)
	repoRegex := regexp.MustCompile(`^https?://[^/]+/[^/]+/[^/]+/projects/\d+$`)

	switch {
	case orgRegex.MatchString(p.URL):
		return v1.OwnerType_OWNER_TYPE_ORGANIZATION
	case userRegex.MatchString(p.URL):
		return v1.OwnerType_OWNER_TYPE_USER
	case repoRegex.MatchString(p.URL):
		return v1.OwnerType_OWNER_TYPE_REPOSITORY
	default:
		return v1.OwnerType_OWNER_TYPE_INVALID
	}
}

func columnResourceID(projectURL string, position int64) string {
	return projectURL + "/columns/" + fmt.Sprint(position)
}
