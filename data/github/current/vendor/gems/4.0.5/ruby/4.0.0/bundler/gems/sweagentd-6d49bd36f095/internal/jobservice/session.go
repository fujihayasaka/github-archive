package jobservice

import (
	"cmp"
	"context"
	"fmt"
	"slices"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
)

// GetSessionClient returns the session for the for the job's actor if the feature
// flag is enabled, otherwise returns a noop session client.
func (s *Service) GetSessionClient(ctx context.Context, agentID int64, ids sweagentd.RepositoryWithActor) (capi.SessionClient, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetSessionClient")
	defer span.End()

	actorID := ids.GetActorID()

	// Check if this is an org-billed job (single type assertion for both session and token logic).
	orgJob, isOrgBilled := ids.(tokens.OrgBillableJob)
	isOrgBilled = isOrgBilled && orgJob.IsBillToOrg()

	// For org-billed jobs, skip the per-user session feature flag check since
	// the actorID is an org ID, not a user ID.
	if !isOrgBilled {
		if !s.ffs.IsEnabledForUser(ctx, capi.CopilotAPIAgentSessions, actorID) {
			return &capi.NoopSessionClient{}, nil
		}
	}

	var token string
	var err error

	if isOrgBilled {
		// Mint an S2S token so CAPI routes billing to the org's seat pool.
		target := sweagentd.ClientTargetForInstallationByOwnerID(agentID, orgJob.GetOwnerID())
		app, appErr := s.appProvider.FindByID(ctx, agentID)
		if appErr != nil {
			return nil, goerrors.Errorf("failed to find app for agent ID %d: %w", agentID, appErr)
		}
		token, err = tokens.GetTokenForJob(ctx, target, agentID, s.twirp.SweagentdAPI(), s.twirp.SweagentdAPI(), app, orgJob, &tokens.NoopCache{})
		if err != nil {
			return nil, goerrors.Errorf("failed to mint org S2S token for repo: %w", err)
		}
	} else {
		target := sweagentd.ClientTargetForUser(agentID, ids.GetActorID())
		token, err = tokens.GetUserToServerToken(ctx, target, agentID, s.twirp.SweagentdAPI(), ids)
		if err != nil {
			return nil, goerrors.Errorf("failed to mint user-to-server token for repo: %w", err)
		}
	}
	config := capi.SessionClientConfig{
		RetryNotFoundErrors:     s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentBackoffSessionClientRetryNotFound, ids),
		RetryUnauthorizedErrors: s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentBackoffSessionClientRetryUnauthorized, ids),
	}

	return s.capi.NewSessionClient(actorID, token, config), nil
}

// GetSessionForJob retrieves the session for the job using its session ID.
//
// Deprecated: this is a temporary function to aid in the migration to jobservice.
// Moving forward, sessions will be managed exclusively by jobservice, external
// callers should not need to explicitly get sessions.
func (s *Service) GetSessionForJob(ctx context.Context, job *jobs.Job) (*capi.Session, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetSessionForJob")
	defer span.End()

	// When UseAsyncSessions is true, sessions are managed by an upstream service, not sweagentd.
	if job.UseAsyncSessions {
		s.obsv.LoggerWithTelemetry(ctx).Info("skipping get session for async sessions job")
		return nil, nil
	}

	sessionClient, err := s.GetSessionClient(ctx, job.AgentID, job)
	if err != nil {
		return nil, goerrors.Errorf("failed to get session client: %w", err)
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

	// When UseAsyncSessions is true, sessions are managed by an upstream service, not sweagentd.
	if job.UseAsyncSessions {
		s.obsv.LoggerWithTelemetry(ctx).Info("skipping session update for async sessions job")
		return nil
	}

	return s.updateSession(ctx, nil, job, update)
}

// StoreGeneratedPullData persists agent-generated PR metadata to the session
// so Mission Control can use it for deferred PR creation.
//
// Unlike UpdateSession, this method intentionally does NOT skip async-session
// jobs. GeneratedPullData originates from sweagentd's progress processing
// (sessions-v2 pr_summary) and must reach the upstream session store
// regardless of who manages the session lifecycle.
func (s *Service) StoreGeneratedPullData(ctx context.Context, job *jobs.Job, title, description string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.StoreGeneratedPullData")
	defer span.End()

	if title == "" && description == "" {
		return nil
	}

	return s.updateSession(ctx, nil, job, capi.SessionUpdate{
		GeneratedPullData: &capi.GeneratedPullData{
			Title:       title,
			Description: description,
		},
	})
}

// GetPreviousJobContext queries previous jobs for the assignment once and
// extracts session IDs (for session history), the most recent ComputeID
// from the same actor (for sandbox resume), and its LaunchedAt timestamp
// (for token expiry checks).
func (s *Service) GetPreviousJobContext(ctx context.Context, job *jobs.Job) (previousSessionIDs []string, previousComputeID string, previousComputeLaunchedAt int64) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetPreviousJobContext")
	defer span.End()

	summaries, err := s.store.GetJobSummariesForAssignmentID(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get job summaries for assignment")
		return nil, "", 0
	}

	if len(summaries) == 0 {
		return nil, "", 0
	}

	// Sort by CreatedAt descending so session IDs are ordered most recent first,
	// matching the contract documented on LaunchAgentOpts.PreviousSessionIDs.
	slices.SortFunc(summaries, func(i, j *jobs.JobSummary) int {
		return cmp.Compare(j.CreatedAt, i.CreatedAt)
	})

	var bestCompute *jobs.JobSummary
	for _, js := range summaries {
		if js.ID == job.ID || js.CreatedAt > job.CreatedAt {
			continue
		}

		// Session IDs — all previous jobs regardless of actor.
		if js.SessionID != "" {
			previousSessionIDs = append(previousSessionIDs, js.SessionID)
		}

		// ComputeID — scoped to the same actor for sandbox resume.
		if js.ComputeID != "" && js.ActorID == job.ActorID {
			if bestCompute == nil || js.CreatedAt > bestCompute.CreatedAt {
				bestCompute = js
			}
		}
	}

	if bestCompute != nil {
		previousComputeID = bestCompute.ComputeID
		previousComputeLaunchedAt = bestCompute.LaunchedAt
	}

	return previousSessionIDs, previousComputeID, previousComputeLaunchedAt
}

// createSessionForJob creates a session for the job with the provided state and name.
func (s *Service) createSessionForJob(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, sessionState capi.SessionState, sessionName string) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.createSessionForJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("creating session for job")

	var err error
	if sessionClient == nil {
		sessionClient, err = s.GetSessionClient(ctx, job.AgentID, job)
		if err != nil {
			return "", goerrors.Errorf("failed to get session client: %w", err)
		}
	}

	agentTaskID := ""
	if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTaskAPI, job) {
		// Append the agentTaskID only if the feature flag is enabled
		// This allows us to gradually roll out the feature since agentTaskID is omitted if empty on the CAPI client
		agentTaskID = job.AssignmentID
	}

	// Strip the CAPI prefix from the model before sending to the session service.
	// The prefix is an implementation detail that should not be exposed externally.
	sessionModel := stripModelPrefix(job.Model)

	resourceType := capi.ResourceTypePullRequest
	if job.PullRequestID == 0 {
		resourceType = ""
	}

	sessionCreate := capi.SessionCreate{
		Name:             sessionName,
		OwnerID:          uint64(job.OwnerID),
		RepoID:           uint64(job.RepoID),
		ResourceID:       job.PullRequestID,
		ResourceNumber:   job.PullRequestNumber,
		ResourceType:     resourceType,
		EventURL:         job.EventURL,
		EventType:        string(job.EventType),
		EventIdentifiers: job.EventIdentifiers,
		EventContent:     job.EventContent,
		State:            sessionState,
		Model:            sessionModel,
		AgentTaskID:      agentTaskID,
		HeadRef:          job.BranchName,
		BaseRef:          job.BaseCommit,
	}

	session, err := sessionClient.CreateSession(ctx, sessionCreate)
	if err != nil {
		return "", goerrors.Errorf("failed to create session: %w", err)
	}

	job.SessionID = session.ID

	s.updateRequestContextJob(ctx, job)
	s.addRequestCtxSessionFromJob(ctx, job)

	return session.ID, nil
}

// getSessionForJob retrieves the session for the job using its session ID.
func (s *Service) getSessionForJob(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job) (*capi.Session, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.getSessionForJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("getting session for job")

	if job.SessionID == "" {
		return nil, goerrors.New("job does not have a session ID")
	}

	session, err := sessionClient.GetSession(ctx, job.SessionID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get session: %w", err)
	}
	if session == nil {
		return nil, goerrors.New("session not found")
	}
	s.addRequestContextSession(ctx, session)

	return session, nil
}

// updateSession updates the session for the job with the provided update details.
func (s *Service) updateSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, update capi.SessionUpdate) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.updateSession")
	defer span.End()

	if job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("session ID is empty, skipping session update")
		return nil
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("updating session for job")

	var err error
	if sessionClient == nil {
		sessionClient, err = s.GetSessionClient(ctx, job.AgentID, job)
		if err != nil {
			return goerrors.Errorf("failed to create session client: %w", err)
		}
	}

	err = sessionClient.UpdateSession(ctx, job.SessionID, update)
	if err != nil {
		return goerrors.Errorf("failed to update session: %w", err)
	}
	s.updateRequestContextSession(ctx, update)

	return nil
}

// finalizeUnexecutedSession finalizes the session for unexecuted job by updating its state based on the job status.
func (s *Service) finalizeUnexecutedSession(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, jobError *jobs.JobError) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.finalizeUnexecutedSession")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing session")

	if job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("no session ID found for job")
		return nil
	}

	var err error
	if sessionClient == nil {
		sessionClient, err = s.GetSessionClient(ctx, job.AgentID, job)
		if err != nil {
			return goerrors.Errorf("failed to create session client: %w", err)
		}
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("getting session for job")

	session, err := s.getSessionForJob(ctx, sessionClient, job)
	if err != nil {
		return goerrors.Errorf("failed to get session: %w", err)
	}
	if session == nil {
		return goerrors.New("session not found")
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
	if jobError.Message != "" && jobError.ResponseStatusCode != "" {
		sessionUpdate.Error = &capi.SessionError{Code: fmt.Sprintf("%s:%s", jobError.Service, jobError.ResponseStatusCode), Message: jobError.Message}
	} else if session.State == capi.SessionStateFailed {
		s.obsv.LoggerWithTelemetry(ctx).Info("failing unexecuted session but not providing an error message or code")
	}

	err = s.updateSession(ctx, sessionClient, job, sessionUpdate)
	if err != nil {
		return goerrors.Errorf("failed to update session: %w", err)
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
