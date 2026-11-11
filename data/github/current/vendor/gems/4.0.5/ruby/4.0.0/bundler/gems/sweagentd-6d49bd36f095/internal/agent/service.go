// Package agent provides services used by the agent while executing jobs.
package agent

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agent/sessionsv2"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/integrations"
	"github.com/github/sweagentd/internal/jobs"
	jobevents "github.com/github/sweagentd/internal/jobs/jobevents"
	"github.com/github/sweagentd/internal/jobs/progress"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

// JobEventEmitter defines the interface for emitting job-related events.
type JobEventEmitter interface {
	EmitJobProgress(ctx context.Context, job *jobs.Job, progress *jobevents.ProgressUpdate, obsv observability.Exporters)
}

type jobstore interface {
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)
	GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error)
	PatchJob(ctx context.Context, job *jobs.Job, patch db.JobPatch, opts ...db.PatchJobOption) error
}

type progressstore interface {
	CreateProgress(ctx context.Context, progress *progress.Progress) (*progress.Progress, error)
	BatchCreateProgress(ctx context.Context, progresses []*progress.Progress) ([]*progress.Progress, error)
	ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error)
	ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error)
}

// GeneratedPullDataStorer persists agent-generated PR title and description
// for deferred PR creation. The implementation must work for async-session
// jobs (sessions-v2 pr_summary) where the session is managed upstream.
type GeneratedPullDataStorer interface {
	StoreGeneratedPullData(ctx context.Context, job *jobs.Job, title, description string) error
}

// Service provides methods for agents to interact with jobs and progress updates.
type Service struct {
	store interface {
		jobstore
		progressstore
	}
	cpf            github.ClientFactoryInterface
	customAgentSvc *customagent.Service
	pluginSvc      *plugins.Service
	obsv           observability.Exporters
	ff             featureflags.Client
	ghtwirp        githubtwirp.ClientInterface
	eventEmitter   JobEventEmitter
	appProvider    *agenticapp.Provider
	oidcSvc        *oidc.Service
	pullDataStorer GeneratedPullDataStorer

	platformClientID string
}

// NewService creates a new Service instance with the provided GitHub client factory.
func NewService(
	store interface {
		jobstore
		progressstore
	},
	cpf github.ClientFactoryInterface,
	customAgentSvc *customagent.Service,
	pluginSvc *plugins.Service,
	obsv observability.Exporters,
	ff featureflags.Client,
	ghtwirp githubtwirp.ClientInterface,
	eventEmitter JobEventEmitter,
	appProvider *agenticapp.Provider,
	pullDataStorer GeneratedPullDataStorer,
	oidcService *oidc.Service,
) *Service {
	return &Service{
		store:          store,
		cpf:            cpf,
		customAgentSvc: customAgentSvc,
		pluginSvc:      pluginSvc,
		obsv:           obsv,
		ff:             ff,
		ghtwirp:        ghtwirp,
		eventEmitter:   eventEmitter,
		appProvider:    appProvider,
		pullDataStorer: pullDataStorer,
		oidcSvc:        oidcService,
	}
}

// GetJob retrieves a job by its ID.
func (s *Service) GetJob(ctx context.Context, id string) (*jobs.Job, error) {
	jobID, err := NewJobID(id)
	if err != nil {
		return nil, err
	}

	job, err := s.store.GetJob(ctx, jobID.Owner, jobID.Repo, jobID.Value)
	if err != nil {
		return nil, err
	}
	if job == nil {
		return nil, ErrJobNotFound
	}

	return job, nil
}

// GetProgress retrieves progress updates for a job.
//
// If namespaces is empty, all progress updates are returned. Otherwise, only
// progress updates matching the provided namespaces are returned.
//
// If includeHistory is true, progress updates from previous jobs for the same
// assignment are also included. When targetSessionID is empty, only the most
// recent previous job's progress is included (existing behavior). When
// targetSessionID is non-empty, the previous-job walk-back searches for a job
// whose `cca-v3-agent` `session-events` records contain a matching sessionId
// — needed for resume-after-permission-timeout, where an unrelated newer job
// in the same assignment would otherwise shadow the target session's snapshot.
func (s *Service) GetProgress(ctx context.Context, job *jobs.Job, namespaces []string, includeHistory bool, targetSessionID string) ([]*progress.Progress, error) {
	progressList, err := s.getProgress(ctx, job.AssignmentID, job.ID, namespaces)
	if err != nil {
		return nil, err
	}

	if !includeHistory {
		return progressList, nil
	}

	previousJobs := s.getPreviousJobs(ctx, job)
	if len(previousJobs) == 0 {
		return progressList, nil
	}

	historicalProgressList := s.findHistoricalProgressForSession(ctx, previousJobs, namespaces, targetSessionID)
	return append(historicalProgressList, progressList...), nil
}

// CreateProgress creates one or more progress updates for a job.
func (s *Service) CreateProgress(ctx context.Context, job *jobs.Job, progressList []*progress.Progress) ([]*progress.Progress, error) {
	var createdProgressList []*progress.Progress
	var err error

	switch len(progressList) {
	case 0:
		return []*progress.Progress{}, nil
	case 1:
		createdProgress, err := s.store.CreateProgress(ctx, progressList[0])
		if err != nil {
			return nil, err
		}
		createdProgressList = []*progress.Progress{createdProgress}
	default:
		createdProgressList, err = s.store.BatchCreateProgress(ctx, progressList)
		if err != nil {
			return nil, err
		}
	}

	// Post-store processing: event emission and side-effects.
	var sideEffectItems []sessionsv2.ProgressItem
	var sessionsV2Items []sessionsV2ProgressItem

	for _, p := range createdProgressList {
		// Emit job progress events.
		// - Integrator namespaces always emit (not gated by UseAsyncSessions).
		// - Session namespaces only emit when UseAsyncSessions is true.
		if s.eventEmitter != nil {
			if integrations.IsProgressNamespace(p.Namespace) || (isSessionNamespace(p.Namespace) && job.UseAsyncSessions) {
				s.emitProgressEvent(ctx, job, p)
			}
		}

		// Collect items for side-effect extraction.
		if p.Namespace == sessionsv2.Namespace {
			contentJSON, jsonErr := json.Marshal(p.Content)
			if jsonErr != nil {
				s.obsv.LogAndReportError(ctx, jsonErr, "failed to marshal progress content for side-effect extraction")
				continue
			}
			sideEffectItems = append(sideEffectItems, sessionsv2.ProgressItem{
				Namespace: p.Namespace,
				Kind:      p.Kind,
				Content:   string(contentJSON),
			})
			sessionsV2Items = append(sessionsV2Items, sessionsV2ProgressItem{
				progress:    p,
				contentJSON: contentJSON,
			})
		}
	}

	// Publish Hydro telemetry for sessions-v2 progress items (Copilot coding agent only).
	if s.appProvider != nil && s.appProvider.IsCopilotCodingAgentApp(job.AgentID) {
		s.publishSessionsV2Telemetry(ctx, job, sessionsV2Items)
	}

	// Dispatch side-effects (PR updates, comment replies).
	s.dispatchSideEffects(ctx, job, sideEffectItems)

	return createdProgressList, nil
}

// ListAgentsByRepoID is a passthrough to customagent.Service.ListAgentsByRepoID for the given user and job's repository.
// However, in this use of the API we will always omit agents with parsing errors. Furthermore, we will
// only list agents that apply to "github-copilot". (So, anything with `target: vscode` would be excluded.)
func (s *Service) ListAgentsByRepoID(ctx context.Context, userInfo *requestctx.UserInfo, job *jobs.Job, skipAuthCheck bool) ([]sweagentd.CustomAgent, error) {
	return s.customAgentSvc.ListAgentsByRepoID(
		ctx,
		uint64(job.RepoID),
		customagent.ListAgentsOpts{
			ExcludeInvalidConfig: true,
			DedupeNames:          true,
			IncludeSources:       []string{customagent.SourceTypeRepo, customagent.SourceTypeOrg, customagent.SourceTypeEnterprise},
			Target:               "github-copilot",
			UserID:               userInfo.ID,
			SkipAuthCheck:        skipAuthCheck,
		})
}

// ResolveAgentForJob is mainly a passthrough to customagent.Service.ResolveByNameAndRepoID for the given user and job's repository.
func (s *Service) ResolveAgentForJob(ctx context.Context, userInfo *requestctx.UserInfo, job *jobs.Job, agentName, version string) (sweagentd.CustomAgent, error) {
	return s.customAgentSvc.ResolveByNameAndRepoID(ctx, uint64(job.RepoID), agentName, version, customagent.ResolveByNameOpts{UserID: userInfo.ID, ErrorOnInvalidConfig: true})
}

// GetAgentForJob resolves the custom agent for a job. When the job has no custom agent
// (i.e. copilot is the default), it checks whether the AgenticApp has an AgentSource.
// If so, it uses the plugin service to fetch a "main" agent from that source.
func (s *Service) GetAgentForJob(ctx context.Context, job *jobs.Job, app sweagentd.AgenticApp) (sweagentd.CustomAgent, *plugins.Plugin, bool, error) {
	agent, err := s.customAgentSvc.FromDB(ctx, job.CustomAgent)
	if err != nil {
		return nil, nil, false, err
	}

	// If the resolved agent is not copilot, return it as is.
	if _, isCopilot := agent.(*customagent.CopilotAgent); !isCopilot {
		return agent, nil, false, nil
	}

	pluginAgent, plugin, err := s.pluginSvc.GetCustomAgentForApp(ctx, app)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to get custom agent for app, falling back to default agent")
		return agent, plugin, false, nil
	}
	if pluginAgent == nil {
		s.obsv.LoggerWithTelemetry(ctx).Info("no custom agent found for app, falling back to default agent")
		return agent, plugin, false, nil
	}

	return pluginAgent, plugin, true, nil
}

// CustomAgentsEnabledForJob is a passthrough to customagent.Service.IsEnabledForRepo which checks if custom agents are enabled for the given repository.
func (s *Service) CustomAgentsEnabledForJob(ctx context.Context, userID int64, job *jobs.Job) bool {
	return s.customAgentSvc.IsEnabledForRepo(ctx, userID, job.OwnerID, job.RepoID)
}

// GetOrganizationCustomInstructions fetches organization custom instructions for a job.
// Returns empty string if the job has no organization (OwnerID == 0).
func (s *Service) GetOrganizationCustomInstructions(ctx context.Context, userID int64, job *jobs.Job) (string, error) {
	ownerID := job.OwnerID

	if ownerID == 0 {
		return "", nil
	}

	req := &sweagentdv1.GetOrganizationCustomInstructionsRequest{
		OrganizationId: uint64(ownerID),
	}

	resp, err := s.ghtwirp.SweagentdAPI().GetOrganizationCustomInstructions(ctx, req)
	if err != nil {
		s.obsv.Logger.WithContext(ctx).Info("failed to get organization custom instructions")
		return "", err
	}

	return resp.OrganizationCustomInstructions, nil
}

// OrganizationCCARunnerSettings holds the CCA runner settings for an organization.
type OrganizationCCARunnerSettings struct {
	Runner                       organizationCCARunnerSettingsRunner
	AllowRepositoryCustomization bool
}

// organizationCCARunnerSettingsRunner is a sealed interface for the runner oneof.
type organizationCCARunnerSettingsRunner interface {
	isOrganizationCCARunnerSettingsRunner()
}

// StandardRunner indicates the standard GitHub-hosted runner.
type StandardRunner struct{}

// LabeledRunner indicates a runner identified by custom labels.
type LabeledRunner struct {
	Labels []string
	Group  string
}

func (*StandardRunner) isOrganizationCCARunnerSettingsRunner() {}
func (*LabeledRunner) isOrganizationCCARunnerSettingsRunner()  {}

// GetOrganizationCCARunnerSettings fetches CCA runner settings for an organization.
// Returns default settings (standard runner, no customization) if the job has no organization (OwnerID == 0).
func (s *Service) GetOrganizationCCARunnerSettings(ctx context.Context, job *jobs.Job) (*OrganizationCCARunnerSettings, error) {
	ownerID := job.OwnerID

	if ownerID == 0 {
		return &OrganizationCCARunnerSettings{
			Runner:                       &StandardRunner{},
			AllowRepositoryCustomization: false,
		}, nil
	}

	req := &sweagentdv1.GetOrganizationCCARunnerSettingsRequest{
		OrganizationId: uint64(ownerID),
	}

	resp, err := s.ghtwirp.SweagentdAPI().GetOrganizationCCARunnerSettings(ctx, req)
	if err != nil {
		s.obsv.Logger.WithContext(ctx).Info("failed to get organization CCA runner settings")
		return nil, err
	}

	settings := &OrganizationCCARunnerSettings{
		AllowRepositoryCustomization: resp.AllowRepositoryCustomization,
	}

	switch resp.GetRunner().(type) {
	case *sweagentdv1.GetOrganizationCCARunnerSettingsResponse_LabeledRunner:
		settings.Runner = &LabeledRunner{Labels: resp.GetLabeledRunner().GetLabels(), Group: resp.GetLabeledRunner().GetGroup()}
	default:
		settings.Runner = &StandardRunner{}
	}

	return settings, nil
}

// resumeWalkBackLimit caps how many previous jobs the resume snapshot search
// inspects. Assignments don't have unbounded job counts in practice, but a
// misconfigured or malicious client should not be able to trigger a full
// per-assignment scan.
const resumeWalkBackLimit = 50

// findHistoricalProgressForSession returns historical progress for the most
// recent previous job (when targetSessionID is empty), or — when targetSessionID
// is set — walks back through previousJobs (capped at resumeWalkBackLimit)
// looking for a job whose `cca-v3-agent` `session-events` records contain a
// matching sessionId, returning that job's progress. Returns an empty slice
// (never an error) on store failures so callers can degrade to "no history".
func (s *Service) findHistoricalProgressForSession(
	ctx context.Context,
	previousJobs []*jobs.JobSummary,
	namespaces []string,
	targetSessionID string,
) []*progress.Progress {
	logger := s.obsv.LoggerWithTelemetry(ctx)

	if targetSessionID == "" {
		previousJob := previousJobs[0]
		historical, err := s.getProgress(ctx, previousJob.AssignmentID, previousJob.ID, namespaces)
		if err != nil {
			s.obsv.LogAndReportError(ctx, err, "failed to get historical progress for previous job")
			return nil
		}
		return historical
	}

	walkLimit := min(len(previousJobs), resumeWalkBackLimit)

	for i := range walkLimit {
		previousJob := previousJobs[i]
		historical, err := s.getProgress(ctx, previousJob.AssignmentID, previousJob.ID, namespaces)
		if err != nil {
			// If we can't fetch a particular job's progress, skip it rather than aborting the search.
			s.obsv.LogAndReportError(ctx, err, "failed to get historical progress while resolving target session")
			continue
		}
		if progressContainsSession(historical, targetSessionID) {
			logger.Info(
				"resume-target session matched in previous job",
				kvp.String("target_session_id", targetSessionID),
				kvp.String("matched_job_id", previousJob.ID),
				kvp.Int("walk_back_index", i),
			)
			return historical
		}
	}

	logger.Info(
		"resume-target session not found in previous jobs",
		kvp.String("target_session_id", targetSessionID),
		kvp.Int("jobs_inspected", walkLimit),
	)
	return nil
}

// progressContainsSession reports whether any record in `records` is a v3
// session-events snapshot whose body declares the given sessionID. Mirrors
// the runtime-side schema in apps/cca-v3/sessionHistory.ts.
func progressContainsSession(records []*progress.Progress, sessionID string) bool {
	const ccaV3Namespace = "cca-v3-agent"
	const sessionEventsKind = "session-events"

	type record struct {
		SessionID string `json:"sessionId"`
	}

	for _, p := range records {
		if p == nil || p.Namespace != ccaV3Namespace || p.Kind != sessionEventsKind {
			continue
		}

		// Content may be a struct/map (deserialized progress) or a JSON
		// string (some transports). Try the typed path first; fall back
		// to parsing a string body if the typed path didn't recognize the
		// content.
		if body, ok := progress.GetContent[record](p); ok && body.SessionID == sessionID {
			return true
		}
		if rawStr, ok := p.Content.(string); ok {
			var inner record
			err := json.Unmarshal([]byte(rawStr), &inner)
			if err == nil && inner.SessionID == sessionID {
				return true
			}
		}
	}
	return false
}

// isSessionNamespace reports whether the given namespace is a session namespace
// (sessions-legacy or sessions-v2) whose emission is gated by UseAsyncSessions.
func isSessionNamespace(ns string) bool {
	return ns == jobevents.SessionsLegacyNamespace || ns == sessionsv2.Namespace
}

// emitProgressEvent translates and emits a single progress event for async sessions.
func (s *Service) emitProgressEvent(ctx context.Context, job *jobs.Job, p *progress.Progress) {
	var emitNamespace string
	var emitKind string
	var emitContent []byte

	switch {
	case integrations.IsProgressNamespace(p.Namespace):
		// First-party integrator namespaces: pass through as-is.
		contentJSON, jsonErr := json.Marshal(p.Content)
		if jsonErr != nil {
			s.obsv.LogAndReportError(ctx, jsonErr, "failed to marshal integrator progress content for event emission")
			return
		}
		emitNamespace = p.Namespace
		emitKind = p.Kind
		emitContent = contentJSON

	case p.Namespace == jobevents.SessionsLegacyNamespace:
		contentJSON, jsonErr := json.Marshal(p.Content)
		if jsonErr != nil {
			s.obsv.LogAndReportError(ctx, jsonErr, "failed to marshal progress content for event emission")
			return
		}
		emitNamespace = p.Namespace
		emitKind = p.Kind
		emitContent = contentJSON

	case p.Namespace == sessionsv2.Namespace:
		if sessionsv2.IsSideEffectKind(p.Kind) {
			return
		}

		// Translate sessions-v2 events to the sessions-legacy wire format before
		// emission so downstream consumers (Mission Control, VS Code) only need
		// to understand the single sessions-legacy format for now.
		contentJSON, jsonErr := json.Marshal(p.Content)
		if jsonErr != nil {
			s.obsv.LogAndReportError(ctx, jsonErr, "failed to marshal sessions-v2 content")
			return
		}
		result, translateErr := sessionsv2.TranslateWithKind(p.Kind, contentJSON)
		if translateErr != nil {
			s.obsv.LogAndReportError(ctx, translateErr, "failed to translate sessions-v2 event")
			return
		}
		emitNamespace = jobevents.SessionsLegacyNamespace
		emitKind = result.Kind
		emitContent = result.SessionLog

	default:
		return
	}

	s.eventEmitter.EmitJobProgress(ctx, job, &jobevents.ProgressUpdate{
		Content:   emitContent,
		Namespace: emitNamespace,
		Kind:      emitKind,
		Version:   strconv.FormatInt(p.Version, 10),
		CreatedAt: time.Unix(p.CreatedAt, 0),
	}, s.obsv)
}

// dispatchSideEffects extracts and executes side-effects from progress items.
// Errors are logged but never fail the request — progress is already stored.
func (s *Service) dispatchSideEffects(ctx context.Context, job *jobs.Job, items []sessionsv2.ProgressItem) {
	effects, parseErrs := sessionsv2.ExtractSideEffects(items)
	for _, parseErr := range parseErrs {
		s.obsv.LogAndReportError(ctx, parseErr, "failed to parse side-effect content")
	}

	for _, effect := range effects {
		switch effect.Kind {
		case sessionsv2.KindReportProgress:
			updateErr := s.UpdateJobPullRequestMidSession(ctx, job, ReportProgressContent{
				PRTitle:       effect.ReportProgress.PRTitle,
				PRDescription: effect.ReportProgress.PRDescription,
			})
			if updateErr != nil {
				s.obsv.LogAndReportError(ctx, updateErr, "failed to update pull request from report_progress")
			}

		case sessionsv2.KindCommentReply:
			replyErr := s.ReplyToJobComment(ctx, job, CommentReplyContent{
				CommentID: effect.CommentReply.CommentID,
				Message:   effect.CommentReply.Message,
			})
			if replyErr != nil {
				s.obsv.LogAndReportError(ctx, replyErr, "failed to reply to comment from comment_reply")
			}

		case sessionsv2.KindPRSummary:
			if job.HasPullRequest() {
				updateErr := s.UpdateJobPullRequestPostSession(ctx, job, ReportProgressContent{
					PRTitle:       effect.PRSummary.PRTitle,
					PRDescription: effect.PRSummary.PRDescription,
				})
				if updateErr != nil {
					s.obsv.LogAndReportError(ctx, updateErr, "failed to update pull request from pr_summary")
				}
			} else {
				s.storeGeneratedPullData(ctx, job, effect.PRSummary.PRTitle, effect.PRSummary.PRDescription)
			}

		default:
		}
	}
}

// storeGeneratedPullData persists agent-generated PR metadata so the deferred
// PR creation flow in Mission Control can use it. This is called when a
// sessions-v2 pr_summary event arrives for a job that does not yet have a PR
// (including async-session jobs).
//
// The title/description are set on the in-memory job object to match the legacy
// result-callback behavior. The generated data is also persisted to the upstream
// session store via the configured storer.
func (s *Service) storeGeneratedPullData(ctx context.Context, job *jobs.Job, prTitle, prDescription string) {
	if prTitle == "" && prDescription == "" {
		return
	}

	job.PullRequestTitle = prTitle
	job.PullRequestDescription = prDescription

	if s.pullDataStorer == nil {
		return
	}

	err := s.pullDataStorer.StoreGeneratedPullData(ctx, job, prTitle, prDescription)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to store generated pull data from pr_summary")
	}
}

// getProgress retrieves progress updates for an assignment and job ID.
//
// If namespaces is empty, all progress updates are returned. Otherwise, only
// progress updates matching the provided namespaces are returned.
func (s *Service) getProgress(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error) {
	if len(namespaces) == 0 {
		progressList, err := s.store.ListProgress(ctx, assignmentID, jobID)
		if err != nil {
			return nil, err
		}
		return progressList, nil
	}

	progressList, err := s.store.ListProgressByNamespace(ctx, assignmentID, jobID, namespaces)
	if err != nil {
		return nil, err
	}

	return progressList, nil
}

// getPreviousJobs retrieves previous job (summaries) for the same assignment
// as the provided job, excluding the current job and jobs created after it.
//
// The returned jobs are sorted by creation time, most recent first. So the
// first job in the returned slice is the most recent previous job.
func (s *Service) getPreviousJobs(ctx context.Context, job *jobs.Job) []*jobs.JobSummary {
	s.obsv.LoggerWithTelemetry(ctx).Info("querying for previous jobs")

	allAssignmentJobs, err := s.store.GetJobSummariesForAssignmentID(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		// If we can't get the job (summaries) for the assignment, don't error
		// just return empty list
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to get job (summaries) for assignment")
		return nil
	}

	if len(allAssignmentJobs) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no jobs found for assignment")
		return nil
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("found additional jobs for assignment")

	// Remove current job and any jobs created after it
	previousJobs := slices.DeleteFunc(allAssignmentJobs, func(j *jobs.JobSummary) bool {
		return j.ID == job.ID || j.CreatedAt > job.CreatedAt
	})

	// Check if there are any other jobs after filtering
	if len(previousJobs) == 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("no previous jobs found for assignment after filtering")
		return previousJobs
	}

	// Sort jobs by creation time, most recent first
	slices.SortFunc(previousJobs, func(a, b *jobs.JobSummary) int {
		return cmp.Compare(b.CreatedAt, a.CreatedAt)
	})

	return previousJobs
}

var (
	// ErrInvalidJobIDFormat indicates that the job ID format is invalid.
	ErrInvalidJobIDFormat = errors.New("invalid job ID format")
	// ErrInvalidJobIDOwner indicates that the job ID owner is invalid.
	ErrInvalidJobIDOwner = errors.New("invalid owner in job ID")
	// ErrInvalidJobIDRepo indicates that the job ID repo is invalid.
	ErrInvalidJobIDRepo = errors.New("invalid repo in job ID")
	// ErrJobNotFound indicates that the job was not found.
	ErrJobNotFound = errors.New("job not found")
)
