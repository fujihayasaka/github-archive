package scheduled

import (
	"context"
	"encoding/json"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/tracing"
)

func createEventPayload(ctx context.Context, ghTwirpClient ghtwirp.Client, log logger.Logger, repoID int64, schedule schedules.ScheduleRun) *flowevents.ScheduleEventPayload {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	eventPayload := &flowevents.ScheduleEventPayload{
		Schedule: schedule.Schedule,
	}

	eventPayload.Workflow = schedule.WorkflowFilePath
	if repoID == 0 {
		return eventPayload
	}

	eventDetails, err := ghTwirpClient.GetRepositoryEventDetails(ctx, repoID)
	if err != nil {
		log.Report(ctx, errors.Wrap(err, "failed to get scheduled event details"))
		return eventPayload
	}

	var payload map[string]map[string]any
	if err := json.Unmarshal([]byte(eventDetails), &payload); err != nil {
		log.Report(ctx, errors.Wrap(err, "error unmarshalling event details"))
		return eventPayload
	}

	if repo, ok := payload["repository"]; ok {
		eventPayload.Repository = repo
	}

	if org, ok := payload["organization"]; ok {
		eventPayload.Organization = org
	}

	if enterprise, ok := payload["enterprise"]; ok {
		eventPayload.Enterprise = enterprise
	}

	return eventPayload
}
