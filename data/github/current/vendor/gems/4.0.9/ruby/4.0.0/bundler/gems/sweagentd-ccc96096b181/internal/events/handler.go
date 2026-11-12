package events

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

type EventsHandler interface {
	OnPullRequestCommentCreated(ctx context.Context, event PullRequestCommentCreatedEvent) error
	OnPullRequestReviewSubmit(ctx context.Context, event PullRequestReviewSubmitEvent) error
	OnPullRequestStateChanged(ctx context.Context, event PullRequestStateChangedEvent) error
	OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error
	OnCodeScanningAlertsAssigned(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error
	OnIssueCreated(ctx context.Context, event IssueCreatedEvent) error
	Process(ctx context.Context, event sweagentd.Event) error
}

var (
	_ EventsHandler = &Handler{}
	_ EventsHandler = &NoopHandler{}
)

// jobService defines the methods from the jobservice package that are used by
// the handler.
//
// This interface is currently a placeholder. As we continue to migrate to the
// jobservice package, this interface will shrink to only one or two methods
// specifically required by the handler.
//
// Most methods in this interface today are temporary to facilitate the migration
type jobService interface {
	QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error
	NewJobBuilder(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *jobservice.JobBuilder
	JobBuilderForJob(assignment *jobs.Assignment, job *jobs.Job, repo *gg.Repository) *jobservice.JobBuilderWithAssignmentAndActor
	GetSessionClient(ctx context.Context, agentID int64, ids sweagentd.RepositoryWithActor) (capi.SessionClient, error)
	GetSessionForJob(ctx context.Context, job *jobs.Job) (*capi.Session, error)
	UpdateSession(ctx context.Context, job *jobs.Job, update capi.SessionUpdate) error
}

type jobstore interface {
	GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error)
	GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error)
	GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error)
	DetachAssignmentResource(ctx context.Context, assignment *jobs.Assignment, resource jobs.AssignmentResource) error
	DetachAssignmentResources(ctx context.Context, assignment *jobs.Assignment) error

	GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error)
	UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)

	CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) // used in tests only
	GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error)                 // used in tests only
	CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error)                             // used in tests only
}

type Handler struct {
	obsv         observability.Exporters
	ffClient     featureflags.Client
	jobService   jobService
	jobsStore    jobstore
	jobExecutor  jobexecutor.JobExecutor
	ghTwirp      githubtwirp.ClientInterface
	capiClient   capi.Client
	ghFactory    github.ClientFactoryInterface
	appProvider  *agenticapp.Provider
	customAgents *customagent.Service
}

func NewHandler(
	obsv observability.Exporters,
	capiClient capi.Client,
	ffClient featureflags.Client,
	jobService jobService,
	jobExecutor jobexecutor.JobExecutor,
	jobsStore jobstore,
	ghTwirp githubtwirp.ClientInterface,
	ghFactory github.ClientFactoryInterface,
	appProvider *agenticapp.Provider,
	customAgents *customagent.Service,
) *Handler {
	return &Handler{
		obsv:         obsv,
		ffClient:     ffClient,
		jobsStore:    jobsStore,
		jobService:   jobService,
		jobExecutor:  jobExecutor,
		ghTwirp:      ghTwirp,
		capiClient:   capiClient,
		ghFactory:    ghFactory,
		appProvider:  appProvider,
		customAgents: customAgents,
	}
}

func (h *Handler) Process(ctx context.Context, event sweagentd.Event) error {
	start := time.Now()
	eventType := eventTypeName(event)

	err := processEvent(ctx, h, event)

	outcome := "success"
	if err != nil {
		outcome = "error"
	}
	h.obsv.DistributionMs(ctx, "events.handler_duration_ms", stats.Tags{"event_type": eventType, "outcome": outcome}, time.Since(start))

	if err != nil {
		// Get the agent from the event
		agentID := event.GetAgentID()
		agent, findErr := h.appProvider.FindByID(agentID)
		if findErr != nil {
			return fmt.Errorf("failed to find agentic app by ID: %w", findErr)
		}
		return jobutils.HandleErrorByType(ctx, h.obsv, h.ghFactory, agent, err)
	}
	return nil
}

// eventTypeName returns a snake_case name for the event type for use in metrics.
func eventTypeName(event any) string {
	switch event.(type) {
	case *PullRequestCommentCreatedEvent:
		return "pull_request_comment_created"
	case *PullRequestReviewSubmitEvent:
		return "pull_request_review_submit"
	case *PullRequestStateChangedEvent:
		return "pull_request_state_changed"
	case *WorkflowRunCompletedEvent:
		return "workflow_run_completed"
	case *CodeScanningAlertsAssignmentEvent:
		return "code_scanning_alerts_assignment"
	case *IssueCreatedEvent:
		return "issue_created"
	default:
		return "unknown"
	}
}

func processEvent(ctx context.Context, h EventsHandler, event any) error {
	switch v := event.(type) {
	case *PullRequestCommentCreatedEvent:
		return h.OnPullRequestCommentCreated(ctx, *v)

	case *PullRequestReviewSubmitEvent:
		return h.OnPullRequestReviewSubmit(ctx, *v)

	case *PullRequestStateChangedEvent:
		return h.OnPullRequestStateChanged(ctx, *v)

	case *WorkflowRunCompletedEvent:
		return h.OnWorkflowRunCompleted(ctx, *v)

	case *CodeScanningAlertsAssignmentEvent:
		return h.OnCodeScanningAlertsAssigned(ctx, *v)

	case *IssueCreatedEvent:
		return h.OnIssueCreated(ctx, *v)

	default:
		return fmt.Errorf("unknown event type %T", v)
	}
}

func (h *Handler) assignmentForPR(ctx context.Context, ownerID, repoID int64, prID *int64, prNumber *int) (*jobs.Assignment, error) {
	assignment, err := h.jobsStore.GetAssignmentForPR(ctx, ownerID, repoID, prID, prNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get assignment: %w", err)
	}

	return assignment, nil
}

// getMostRecentJob returns the most recent job from a list of jobs based on CreatedAt.
// Returns nil if the job list is empty.
func getMostRecentJob(allJobs []*jobs.Job) *jobs.Job {
	if len(allJobs) == 0 {
		return nil
	}

	mostRecent := allJobs[0]
	for _, job := range allJobs[1:] {
		if job.CreatedAt > mostRecent.CreatedAt {
			mostRecent = job
		}
	}

	return mostRecent
}
