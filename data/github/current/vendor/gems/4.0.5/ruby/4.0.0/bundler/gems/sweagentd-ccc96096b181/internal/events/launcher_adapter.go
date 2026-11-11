package events

import (
	"context"
	"time"

	"github.com/github/sweagentd/internal/launcher"
)

// LauncherAdapter adapts events.Handler to launcher.WorkflowRunCompletedHandler.
// This allows Docker containers to trigger the same workflow completion flow as GitHub Actions.
type LauncherAdapter struct {
	handler *Handler
}

// NewLauncherAdapter creates a new adapter that wraps an events.Handler
// and implements the launcher.WorkflowRunCompletedHandler interface.
func NewLauncherAdapter(handler *Handler) *LauncherAdapter {
	return &LauncherAdapter{handler: handler}
}

// OnWorkflowRunCompleted implements launcher.WorkflowRunCompletedHandler by converting
// the launcher event interface to the concrete events.WorkflowRunCompletedEvent type.
func (a *LauncherAdapter) OnWorkflowRunCompleted(ctx context.Context, event launcher.WorkflowRunCompletedEvent) error {
	// Convert the launcher interface to the concrete events type
	concreteEvent := WorkflowRunCompletedEvent{
		Repo: &WorkflowRepository{
			ID:      event.GetRepositoryID(),
			OwnerID: event.GetOwnerID(),
		},
		WorkflowRun: &WorkflowRun{
			ID:          event.GetWorkflowRunID(),
			Path:        event.GetWorkflowPath(),
			UserID:      event.GetActorID(),
			Status:      "completed",
			Conclusion:  event.GetConclusion(),
			CompletedAt: event.GetCompletedAt(),
		},
		Timestamp: time.Now(),
	}

	return a.handler.OnWorkflowRunCompleted(ctx, concreteEvent)
}
