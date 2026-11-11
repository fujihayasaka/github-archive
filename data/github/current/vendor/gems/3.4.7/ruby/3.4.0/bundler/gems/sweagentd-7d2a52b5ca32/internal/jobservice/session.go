package jobservice

import (
	"cmp"
	"context"
	"fmt"
	"slices"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
)

// GetSessionForJob retrieves the session for the job using its session ID.
//
// Deprecated: this is a temporary function to aid in the migration to jobservice.
// Moving forward, sessions will be managed exclusively by jobservice, external
// callers should not need to explicitly get sessions.
func (s *Service) GetSessionForJob(ctx context.Context, job *jobs.Job) (*capi.Session, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetSessionForJob")
	defer span.End()

	sessionClient, err := s.getSessionClient(ctx, job)
	if err != nil {
		return nil, fmt.Errorf("failed to get session client: %w", err)
	}
	return s.getSessionForJob(ctx, sessionClient, job)
}

// UpdateSession updates the session for the job with the provided update details.
//
// Deprecated: this is a temporary function to aid in the migration to jobservice.
// Moving forward, sessions will be managed exclusively by jobservice, external
// callers should not need to update sessions.
func (s *Service) UpdateSession(ctx context.Context, job *jobs.Job, update capi.SessionUpdate) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.UpdateSession")
	defer span.End()

	return s.updateSession(ctx, nil, job, update)
}

// FailSession fails the session for the job and updates the session state to
// failed with the provided message.
//
// Deprecated: this is a temporary function to aid in the migration to jobservice.
// Moving forward, sessions will be managed exclusively by jobservice, external
// callers should not need to fail sessions.
func (s *Service) FailSession(ctx context.Context, job *jobs.Job, jobError *joberrors.JobError, errorMessage string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.FailSession")
	defer span.End()

	sessionClient, err := s.getSessionClient(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to get session client: %w", err)
	}
	return s.failSession(ctx, sessionClient, job, jobError, errorMessage)
}

// GetPreviousSessionIDs retrieves previous session IDs for jobs with the same
// assignment ID, excluding the current job and jobs created after it.
//
// Deprecated: this is a temporary function to aid in the migration to jobservice.
// Moving forward, sessions will be managed exclusively by jobservice, external
// callers should not need to get previous session IDs.
func (s *Service) GetPreviousSessionIDs(ctx context.Context, job *jobs.Job) []string {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetPreviousSessionIDs")
	defer span.End()

	return s.getPreviousSessionIDs(ctx, job)
}

// getSessionClient returns a session client for the job's actor if the feature
// flag is enabled, otherwise returns a noop session client.
func (s *Service) getSessionClient(ctx context.Context, job *jobs.Job) (capi.SessionClient, error) {
	return getSessionClient(ctx, s.ffs, s.twirp, s.capi, job)
}

// getSessionClient returns a session client for the job's actor if the feature
// flag is enabled, otherwise returns a noop session client.
func getSessionClient(ctx context.Context, ffs featureflags.Client, twirp githubtwirp.ClientInterface, capiClient capi.Client, ids sweagentd.ActorWithRepository) (capi.SessionClient, error) {
	actorID := ids.GetActorID()
	if !ffs.IsEnabledForUser(ctx, capi.CopilotAPIAgentSessions, actorID) {
		return &capi.NoopSessionClient{}, nil
	}

	token, err := tokens.GetUserToServerToken(ctx, twirp.SweagentdAPI(), ids)
	if err != nil {
		return nil, fmt.Errorf("failed to mint user to server token for repo: %w", err)
	}
	client := capiClient.NewSessionClient(actorID, token)

	return client, nil
}

// createSessionForJob creates a session for the job with the provided state and name.
func (s *Service) createSessionForJob(ctx context.Context, job *jobs.Job, sessionState capi.SessionState, sessionName string) (string, error) {
	sessionClient, err := s.getSessionClient(ctx, job)
	if err != nil {
		return "", fmt.Errorf("failed to get session client: %w", err)
	}

	session, err := sessionClient.CreateSession(ctx, job.OwnerID, job.RepoID, job.PullRequestID, job.EventType, job.EventURL, job.EventIdentifiers, job.EventContent, sessionState, sessionName)
	if err != nil {
		return "", fmt.Errorf("failed to create session: %w", err)
	}

	job.SessionID = session.ID

	s.updateRequestContextJob(ctx, job)

	return session.ID, nil
}

// getSessionForJob retrieves the session for the job using its session ID.
func (s *Service) getSessionForJob(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job) (*capi.Session, error) {
	if job.SessionID == "" {
		return nil, fmt.Errorf("job does not have a session ID")
	}

	session, err := sessionClient.GetSession(ctx, job.SessionID)
	if err != nil {
		return nil, fmt.Errorf("failed to get session: %w", err)
	}
	if session == nil {
		return nil, fmt.Errorf("session not found")
	}
	s.addRequestContextSession(ctx, session)

	return session, nil
}

// updateSession updates the session for the job with the provided update details.
func (s *Service) updateSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, update capi.SessionUpdate) error {
	if job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("session ID is empty, skipping session update")
		return nil
	}

	var err error
	if sessionClient == nil {
		sessionClient, err = s.getSessionClient(ctx, job)
		if err != nil {
			return fmt.Errorf("failed to create session client: %w", err)
		}
	}

	if update.State == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("updating session for job")
	} else {
		s.obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("updating session for job to state %s", update.State))
	}

	if err := sessionClient.UpdateSession(ctx, job.SessionID, update); err != nil {
		return fmt.Errorf("failed to update session: %w", err)
	}
	s.updateRequestContextSession(ctx, update)

	return nil
}

// startSession starts a session for the job and updates the session state to in progress.
func (s *Service) startSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, workflowID uint64) error {
	update := capi.SessionUpdate{WorkflowRunID: workflowID}

	return s.updateSession(ctx, sessionClient, job, update)
}

// failSession fails the session for the job and updates the session state to failed with the provided message.
func (s *Service) failSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, jobError *joberrors.JobError, errorMessage string) error {
	update := capi.SessionUpdate{
		State: capi.SessionStateFailed,
		Error: &capi.SessionError{Code: jobError.String(), Message: errorMessage},
	}
	return s.updateSession(ctx, sessionClient, job, update)
}

// finalizeUnexecutedSession finalizes the session for unexecuted job by updating its state based on the job status.
func (s *Service) finalizeUnexecutedSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, errorMessage string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.finalizeUnexecutedSession")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing session")

	if job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("no session ID found for job")
		return nil
	}

	var err error
	if sessionClient == nil {
		sessionClient, err = s.getSessionClient(ctx, job)
		if err != nil {
			return fmt.Errorf("failed to create session client: %w", err)
		}
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("getting session for job")

	session, err := s.getSessionForJob(ctx, sessionClient, job)
	if err != nil {
		return fmt.Errorf("failed to get session: %w", err)
	}
	if session == nil {
		return fmt.Errorf("session not found")
	}
	s.addRequestContextSession(ctx, session)

	if capi.IsFinalState(session.State) {
		// Session is already in a final state, nothing to do
		s.obsv.LoggerWithTelemetry(ctx).Info("session is already in a final state")
		return nil
	}

	newState := capi.MapJobStatusToSessionState(job.Status)
	if newState == "" {
		s.obsv.LoggerWithTelemetry(ctx).Error("Failed to map job status to session state")
		return nil
	}

	if newState == session.State {
		s.obsv.LoggerWithTelemetry(ctx).Info("session is already in the correct state, nothing to do")
		return nil
	}

	session.State = newState
	sessionUpdate := capi.SessionUpdate{State: session.State}
	if errorMessage != "" {
		sessionUpdate.Error = &capi.SessionError{Message: errorMessage}
	}

	err = s.updateSession(ctx, sessionClient, job, sessionUpdate)
	if err != nil {
		return fmt.Errorf("failed to update session: %w", err)
	}
	s.addRequestContextSession(ctx, session)

	if sessionUpdate.State == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("finalized job session")
	} else {
		s.obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("finalized job session to state %s", sessionUpdate.State))
	}

	return nil
}

// getPreviousSessionIDs retrieves previous session IDs for jobs with the same
// assignment ID, excluding the current job and jobs created after it.
func (s *Service) getPreviousSessionIDs(ctx context.Context, job *jobs.Job) []string {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.getPreviousSessionIDs")
	defer span.End()

	sessionIDs := []string{}

	s.obsv.LoggerWithTelemetry(ctx).Info("querying for previous session IDs")

	jobsForAssignment, err := s.store.GetJobSummariesForAssignmentID(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		// If we can't get the job (summaries) for the assignment, we still proceed with the job execution
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get job (summaries) for assignment")
		return sessionIDs
	}

	if len(jobsForAssignment) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no other jobs for current assignment")
		return sessionIDs
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("found additional jobs for current assignment")

	// Create list we are safe to mutate
	jobsForAssignmentClone := slices.Clone(jobsForAssignment)

	// Remove current job and any jobs created after it
	jobsForAssignmentClone = slices.DeleteFunc(jobsForAssignmentClone, func(j *jobs.JobSummary) bool {
		return j.ID == job.ID || j.CreatedAt > job.CreatedAt
	})

	// Check if there are any other jobs after filtering
	if len(jobsForAssignmentClone) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no other jobs for current assignment after filtering")
		return sessionIDs
	}

	// Sort jobs by creation time, most recent first
	slices.SortFunc(jobsForAssignmentClone, func(i, j *jobs.JobSummary) int {
		return cmp.Compare(j.CreatedAt, i.CreatedAt)
	})

	// Process jobs starting with most recent, skip jobs without a session ID
	for _, jobSummary := range jobsForAssignmentClone {
		// Skip jobs without session IDs, but continue processing
		if jobSummary.SessionID == "" {
			continue
		}
		// Add session ID to list
		sessionIDs = append(sessionIDs, jobSummary.SessionID)
	}

	return sessionIDs
}
