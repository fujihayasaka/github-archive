package jobservice

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/telemetry"
)

// CreateCommandForJob creates a new command for the given job.
func (s *Service) CreateCommandForJob(ctx context.Context, job *jobs.Job, externalID string, actorID int64, content string, timestamp int64) (*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CreateCommandForJob")
	defer span.End()

	if job.IsTerminal() {
		return nil, command.ErrJobIsTerminal
	}
	telemetryPublisher := telemetry.NewTelemetryPublisher(s.obsv, s.twirp, s.ffs)

	command := job.NewCommand(externalID, actorID, content, command.TypeUserMessage, timestamp)
	command, err := s.store.CreateCommand(ctx, command)
	if err != nil {
		return nil, goerrors.Errorf("failed to add command to job: %w", err)
	}

	telemetryPublisher.PublishCommandCreatedTelemetry(ctx, command)

	return command, nil
}

// GetPendingCommandsForJob returns all pending commands for a given job.
func (s *Service) GetPendingCommandsForJob(ctx context.Context, assignmentID, jobID string) ([]*command.Command, error) {
	commands, err := s.store.GetCommandsWithStatus(ctx, assignmentID, jobID, command.StatusPending)
	if err != nil {
		return nil, goerrors.Errorf("failed to get pending commands for job: %w", err)
	}
	return commands, nil
}
