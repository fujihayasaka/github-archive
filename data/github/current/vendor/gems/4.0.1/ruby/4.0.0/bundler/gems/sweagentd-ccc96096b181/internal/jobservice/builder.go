package jobservice

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/aigen"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	limits "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/onboarding"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/tips"
	gg "github.com/google/go-github/v75/github"
)

// BuilderFinalizedJobError is returned when the job builder has encountered a
// "known" error during job building and has finalized the job to a terminal state.
//
// An example of this would be when branch rules are violated and the job and
// session are finalized as "failed" with the specific violations set on the session.
type BuilderFinalizedJobError struct {
	Err error
}

// Error returns the error message for the BuilderFinalizedJobError.
func (e *BuilderFinalizedJobError) Error() string {
	if e.Err == nil {
		return "job builder encountered known error and finalized job"
	}
	return fmt.Sprintf("job builder encountered known error and finalized job: %v", e.Err)
}

// Unwrap returns the underlying error that caused the job to be finalized.
func (e *BuilderFinalizedJobError) Unwrap() error {
	return e.Err
}

// IsBuilderFinalizedJobError checks if the provided error is of type BuilderFinalizedJobError.
func IsBuilderFinalizedJobError(err error) bool {
	var finalizedErr *BuilderFinalizedJobError
	return errors.As(err, &finalizedErr)
}

// Event represents the event details associated with triggering a job.
type Event struct {
	Type        jobs.EventType
	URL         string
	Identifiers []string
	Content     string
}

type branch struct {
	BaseCommit string

	// NameSuffix for the branch (after copilot/). If not set, will default to "<action>-<job id>"
	NameSuffix string
}

type pullRequest struct {
	Title string
	Body  string

	Branch branch
}

type session struct {
	Name string
}

type assignmentLookupByID struct {
	OwnerID      int64
	RepoID       int64
	AssignmentID string
}

type assignmentLookupByResource struct {
	OwnerID  int64
	RepoID   int64
	Resource *jobs.AssignmentResource
}

// JobBuilderOption defines a function type for configuring the JobBuilder.
type JobBuilderOption func(*JobBuilder)

// JobBuilder is a builder for creating and configuring jobs in a fluent manner.
type JobBuilder struct {
	// holds a reference to the job service to use for building the job
	service *Service

	built bool

	actor  jobs.JobActor    // used during job creation
	action jobs.AgentAction // used during job creation

	assignment *jobs.Assignment
	job        *jobs.Job

	defaultBranch string

	assignmentLookupByID       *assignmentLookupByID
	assignmentLookupByResource *assignmentLookupByResource

	jobInitHook func(*jobs.Job)
	jobSaveHook func(*jobs.Job)

	event *Event

	runOptions     jobs.RunOptions
	runOptionsHook func(*jobs.Job) jobs.RunOptions

	requestStartedAt *time.Time

	createSession bool

	commentIDs []int64
	reviewIDs  []int64

	features        jobs.EnvironmentFeatures
	featuresBuilder FeaturesBuilderFunc

	withoutCreatingFeatures bool

	branchRuleViolationHook BranchRuleViolationHookFunc

	problemStatement        jobs.ProblemStatement
	problemStatementBuilder ProblemStatementBuilderFunc

	customAgent sweagentd.CustomAgent

	useAINameGen bool

	agentID int64

	model string

	onboarding bool

	experiments bool

	repo *gg.Repository
}

// JobBuilderWithAssignmentAndActor is a JobBuilder that has been configured with
// an assignment and actor.
type JobBuilderWithAssignmentAndActor struct {
	*JobBuilderWithAssignment
}

// JobBuilderWithAssignment is a JobBuilder that has been configured with an assignment.
type JobBuilderWithAssignment struct {
	*JobBuilder
}

// ForAssignment sets the assignment to use for the job.
func (builder *JobBuilder) ForAssignment(assignment *jobs.Assignment) *JobBuilderWithAssignment {
	builder.assignment = assignment
	return &JobBuilderWithAssignment{builder}
}

// ForAssignmentWithID looks up and sets an existing assignment that will
// be pulled from the database using the provided ownerID, repoID, and assignmentID.
func (builder *JobBuilder) ForAssignmentWithID(ownerID, repoID int64, assignmentID string) *JobBuilderWithAssignment {
	builder.assignmentLookupByID = &assignmentLookupByID{
		OwnerID:      ownerID,
		RepoID:       repoID,
		AssignmentID: assignmentID,
	}
	return &JobBuilderWithAssignment{builder}
}

// ForAssignmentWithResource looks up and sets an existing assignment that will
// be pulled from the database using the provided ownerID, repoID, and resource.
func (builder *JobBuilder) ForAssignmentWithResource(ownerID, repoID int64, resource *jobs.AssignmentResource) *JobBuilderWithAssignment {
	builder.assignmentLookupByResource = &assignmentLookupByResource{
		OwnerID:  ownerID,
		RepoID:   repoID,
		Resource: resource,
	}
	return &JobBuilderWithAssignment{builder}
}

// WithNewAssignment creates and sets a new assignment to use for the job.
func (builder *JobBuilder) WithNewAssignment(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, useAsyncSessions bool, resources ...jobs.AssignmentResource) *JobBuilderWithAssignment {
	builder.assignment = jobs.NewAssignment(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, useAsyncSessions, resources...)
	return &JobBuilderWithAssignment{builder}
}

// WithNewAssignmentWithCustomAgent creates and sets a new assignment with a custom agent for the job
func (builder *JobBuilder) WithNewAssignmentWithCustomAgent(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, useAsyncSessions bool, agent sweagentd.CustomAgent, resources ...jobs.AssignmentResource) *JobBuilderWithAssignment {
	builder.assignment = jobs.NewAssignmentWithCustomAgent(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, useAsyncSessions, agent.ToDB(), resources...)
	return &JobBuilderWithAssignment{builder}
}

// WithActor sets the actor (user) to associate with the job.
func (builder *JobBuilderWithAssignment) WithActor(id int64, login, displayLogin, trackingID string) *JobBuilderWithAssignmentAndActor {
	return builder.WithJobActor(jobs.JobActor{
		ID:           id,
		Login:        login,
		DisplayLogin: displayLogin,
		TrackingID:   trackingID,
	})
}

// WithJobActor sets the actor (user) to associate with the job.
func (builder *JobBuilderWithAssignment) WithJobActor(actor jobs.JobActor) *JobBuilderWithAssignmentAndActor {
	builder.actor = actor
	return &JobBuilderWithAssignmentAndActor{builder}
}

// ForJob sets the job to use for building.
func (builder *JobBuilderWithAssignment) ForJob(job *jobs.Job) *JobBuilderWithAssignmentAndActor {
	builder.job = job
	return builder.WithActor(job.ActorID, job.ActorLogin, job.ActorDisplayLogin, job.ActorAnalyticsTrackingID)
}

// WithJobInitHook sets a hook that is called after the job is initialized but
// before any other processing is done.
func (builder *JobBuilderWithAssignmentAndActor) WithJobInitHook(hook func(*jobs.Job)) *JobBuilderWithAssignmentAndActor {
	builder.jobInitHook = hook
	return builder
}

// WithSaveJobHook sets a hook that is called immediately before saving the job
// to the database.
func (builder *JobBuilderWithAssignmentAndActor) WithSaveJobHook(hook func(*jobs.Job)) *JobBuilderWithAssignmentAndActor {
	builder.jobSaveHook = hook
	return builder
}

// WithEvent sets the event details to associate with the job.
func (builder *JobBuilderWithAssignmentAndActor) WithEvent(event Event) *JobBuilderWithAssignmentAndActor {
	builder.event = &event
	return builder
}

// WithRunOptions sets the run options to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithRunOptions(runOptions jobs.RunOptions) *JobBuilderWithAssignmentAndActor {
	builder.runOptions = runOptions
	return builder
}

// WithRunOptionsHook sets a hook that is called to determine the run options
// to use for the job based on the job details.
func (builder *JobBuilderWithAssignmentAndActor) WithRunOptionsHook(runOptionsHook func(*jobs.Job) jobs.RunOptions) *JobBuilderWithAssignmentAndActor {
	builder.runOptionsHook = runOptionsHook
	return builder
}

// WithRequestStartedAt sets the request start time on the job.
func (builder *JobBuilderWithAssignmentAndActor) WithRequestStartedAt(startedAt time.Time) *JobBuilderWithAssignmentAndActor {
	builder.requestStartedAt = &startedAt
	return builder
}

// WithProblemStatement sets a static problem statement to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithProblemStatement(ps *jobs.ProblemStatement) *JobBuilderWithAssignmentAndActor {
	builder.problemStatement = *ps
	return builder
}

// ProblemStatementBuilderFunc is a function that builds a problem statement based
// on the context and job.
type ProblemStatementBuilderFunc func(ctx context.Context, job *jobs.Job) (jobs.ProblemStatement, error)

// WithProblemStatementBuilder sets a builder function that is called to build
// the problem statement for the job based on the job details.
func (builder *JobBuilderWithAssignmentAndActor) WithProblemStatementBuilder(psBuilder ProblemStatementBuilderFunc) *JobBuilderWithAssignmentAndActor {
	builder.problemStatementBuilder = psBuilder
	return builder
}

// WithCommentIDs sets the comment IDs to associate with the job.
func (builder *JobBuilderWithAssignmentAndActor) WithCommentIDs(commentIDs ...int64) *JobBuilderWithAssignmentAndActor {
	builder.commentIDs = commentIDs
	return builder
}

// WithReviewIDs sets the review IDs to associate with the job.
func (builder *JobBuilderWithAssignmentAndActor) WithReviewIDs(reviewIDs ...int64) *JobBuilderWithAssignmentAndActor {
	builder.reviewIDs = reviewIDs
	return builder
}

// WithFeatures sets the environment features to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithFeatures(features jobs.EnvironmentFeatures) *JobBuilderWithAssignmentAndActor {
	builder.features = features
	return builder
}

// FeaturesBuilderFunc is a function that builds environment features based
// on the context and job.
type FeaturesBuilderFunc func(ctx context.Context, job *jobs.Job) jobs.EnvironmentFeatures

// WithFeaturesBuilder sets a builder function that is called to build the
// environment features for the job based on the job details.
func (builder *JobBuilderWithAssignmentAndActor) WithFeaturesBuilder(featuresBuilder FeaturesBuilderFunc) *JobBuilderWithAssignmentAndActor {
	builder.featuresBuilder = featuresBuilder
	return builder
}

// WithoutCreatingFeatures indicates that no features should be created for the
// job when Build is called. This allows callers to persist the required features
// while deferring the creation of the features until later.
func (builder *JobBuilderWithAssignmentAndActor) WithoutCreatingFeatures() *JobBuilderWithAssignmentAndActor {
	builder.withoutCreatingFeatures = true
	return builder
}

// BranchRuleViolationHookFunc is called when branch rules are violated during job
// creation. It receives the context, GitHub client, actor login, assignment, and the
// result of the rules check. It can be used to notify the user or take other actions.
type BranchRuleViolationHookFunc func(ctx context.Context, gh github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *CheckRulesResult) error

// WithBranchRuleViolationHook sets a hook that is called when branch rules are
// violated during job creation. It receives the context, GitHub client, actor login,
// assignment, and the result of the rules check. It can be used to notify the user
// or take other actions.
func (builder *JobBuilderWithAssignmentAndActor) WithBranchRuleViolationHook(hook BranchRuleViolationHookFunc) *JobBuilderWithAssignmentAndActor {
	builder.branchRuleViolationHook = hook
	return builder
}

// WithNewSession indicates that a new session should be created for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithNewSession() *JobBuilderWithAssignmentAndActor {
	builder.createSession = true
	return builder
}

// WithCustomAgent sets a specific custom agent to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithCustomAgent(agent sweagentd.CustomAgent) *JobBuilderWithAssignmentAndActor {
	builder.customAgent = agent
	return builder
}

// WithAgentID sets the GitHub App ID to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithAgentID(agentID int64) *JobBuilderWithAssignmentAndActor {
	builder.agentID = agentID
	return builder
}

// WithModel sets the AI model to use for the job. If this is just the model ID (ex: "gpt-4o"),
// the builder will prepend the CAPI prefix for the runtime (ex "sweagent-capi:gpt-4o").
// If model is empty, this is a no-op to allow cleaner chaining.
func (builder *JobBuilderWithAssignmentAndActor) WithModel(model string) *JobBuilderWithAssignmentAndActor {
	if model == "" {
		return builder
	}
	builder.model = model
	return builder
}

// WithOnboarding indicates that onboarding features should be applied to the job.
func (builder *JobBuilderWithAssignmentAndActor) WithOnboarding() *JobBuilderWithAssignmentAndActor {
	builder.onboarding = true
	return builder
}

// WithExperiments indicates that experiment assignments should be set for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithExperiments() *JobBuilderWithAssignmentAndActor {
	builder.experiments = true
	return builder
}

// WithAINameGen indicates that session, branch, or pull request names should be generated via AI.
func (builder *JobBuilderWithAssignmentAndActor) WithAINameGen() *JobBuilderWithAssignmentAndActor {
	builder.useAINameGen = true
	return builder
}

// NewJobBuilder creates a new JobBuilder with the given action and default branch provider.
func (s *Service) NewJobBuilder(action jobs.AgentAction, repo *gg.Repository, baseCommit string) *JobBuilder {
	builder := &JobBuilder{
		service:       s,
		defaultBranch: baseCommit,
		action:        action,
		useAINameGen:  false,
		repo:          repo,
	}
	return builder
}

// JobBuilderForJob creates a JobBuilder initialized with the given assignment and job.
func (s *Service) JobBuilderForJob(assignment *jobs.Assignment, job *jobs.Job, repo *gg.Repository) *JobBuilderWithAssignmentAndActor {
	return s.
		NewJobBuilder(job.Action, repo, job.BaseCommit).
		ForAssignment(assignment).
		ForJob(job)
}

// determinePullRequestCreation determines if a new pull request should be created
// and returns the corresponding branch and pull request configurations.
func (builder *JobBuilder) determinePullRequestCreation(defaultBranchNameSuffix string) *pullRequest {
	if builder.job.HasPullRequest() || !builder.job.RequiresPullRequest() || builder.withoutCreatingFeatures {
		return nil
	}

	newPullRequest := &pullRequest{
		Title: builder.job.Features.PullRequest.TitlePlaceholder,
		Body:  builder.job.Features.PullRequest.BodyPlaceholder + builder.job.Features.PullRequest.BodySuffix,
	}

	// A HeadRef specified in the pull request feature takes precedence
	// and means we don't need to create a new branch
	if builder.job.Features.PullRequest.HeadRef != "" {
		builder.job.BranchName = builder.job.Features.PullRequest.HeadRef
		return newPullRequest
	}

	newBranch := &branch{
		BaseCommit: builder.job.Features.PullRequest.BaseRef,
		NameSuffix: "",
	}
	if builder.job.Features.Branch != nil {
		// if branch feature is specified, use its details for the branch
		newBranch = &branch{
			BaseCommit: builder.job.Features.Branch.BaseRef,
			NameSuffix: builder.job.Features.Branch.Name,
		}
	}
	// if no branch name suffix provided, default to <action>-<job id>
	if newBranch.NameSuffix == "" {
		newBranch.NameSuffix = defaultBranchNameSuffix
	}

	newPullRequest.Branch = *newBranch
	return newPullRequest
}

// Build constructs the job and resources based on the provided configuration and
// saves it to the database.
//
// If the error returned is of type [BuilderFinalizedJobError], it indicates that
// the job encountered a known error type during building and has been finalized
// to gracefully handle the error. This is only applicable for some asynchronous
// scenarios where the job and session were created but could not proceed due to
// specific conditions.
//
// For example, if branch rules were violated, the job and session would be finalized
// to "failed" with the specific violations set on the session to communicate the
// reason for failure to the user.
//
//nolint:maintidx // Maintainability index is high due to the complexity of building jobs with many options.
func (builder *JobBuilderWithAssignmentAndActor) Build(ctx context.Context, gh github.ClientInterface) (*jobs.Assignment, *jobs.Job, error) {
	ctx, span := builder.service.obsv.Tracer.Start(ctx, "jobservice.BuildJob")
	defer span.End()

	// If we just created the assignment in WithNewAssignment, and the user called
	// WithCustomAgent to set a custom agent, make sure to set it on the assignment.
	if builder.assignment != nil && !builder.assignment.Persisted() &&
		!builder.assignment.HasCustomAgent() && builder.customAgent != nil {
		builder.assignment.CustomAgent = builder.customAgent.ToDB()
	}

	//nolint:nestif // because this is clearer to read
	if builder.assignment == nil {
		// existing assignment lookup
		if builder.assignmentLookupByID != nil {
			assignment, err := builder.service.store.GetAssignment(ctx,
				builder.assignmentLookupByID.OwnerID,
				builder.assignmentLookupByID.RepoID,
				builder.assignmentLookupByID.AssignmentID,
			)
			if err != nil {
				return nil, nil, goerrors.Errorf("failed to get assignment by ID: %w", err)
			}
			if assignment == nil {
				return nil, nil, goerrors.New("no assignment found with ID")
			}
			builder.assignment = assignment
		}

		if builder.assignmentLookupByResource != nil {
			assignment, err := builder.service.store.GetAssignmentForResource(ctx,
				builder.assignmentLookupByResource.OwnerID,
				builder.assignmentLookupByResource.RepoID,
				*builder.assignmentLookupByResource.Resource,
			)
			if err != nil {
				return nil, nil, goerrors.Errorf("failed to get assignment for resource: %w", err)
			}
			if assignment == nil {
				return nil, nil, goerrors.New("no assignment found for resource")
			}
			builder.assignment = assignment
		}
	}

	if builder.assignment == nil {
		return nil, nil, goerrors.New("no assignment provided")
	}

	// An assignment will have a value for ETag if it already exists in the
	// database. If the builder.assignment came from the database, don't save
	// it again unless we made changes to it.
	saveAssignment := !builder.assignment.Persisted()

	if builder.actor.DisplayLogin == "" {
		displayLogin, err := builder.service.resolveActorDisplayLogin(ctx, &builder.actor)
		if err != nil {
			return nil, nil, err
		}
		builder.actor.DisplayLogin = displayLogin
	}

	if builder.job == nil {
		// new builder.job
		builder.job = builder.assignment.NewJob(builder.action, builder.actor, builder.defaultBranch)
	}

	// job init hook to customize job before other processing
	if builder.jobInitHook != nil {
		builder.jobInitHook(builder.job)
	}
	builder.service.updateRequestContextJob(ctx, builder.job)

	// if we just created the job the actor will already match, but we also
	// support loading an existing job and updating it with a new actor
	// this should only happen for pending jobs that receive new actionable events
	if builder.job.ActorID != builder.actor.ID {
		// TODO (colbylwilliams): should we check for pending status here?
		builder.job.ActorID = builder.actor.ID
		builder.job.ActorLogin = builder.actor.Login
		builder.job.ActorDisplayLogin = builder.actor.DisplayLogin
		builder.job.ActorAnalyticsTrackingID = builder.actor.TrackingID
		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// check up-front (before creating the job, session, pr, etc.) if the actor
	// has already exceeded the max queued jobs and fail fast
	builder.service.obsv.LoggerWithTelemetry(ctx).Info("checking if actor has exceeded the maximum number of queued jobs")
	if builder.service.limiter.QueuedJobsExceeded(ctx, builder.job.ActorID) {
		builder.service.obsv.LoggerWithTelemetry(ctx).
			WithError(limits.ErrActorExceededMaxQueuedJobs).Error("actor has exceeded maximum queued jobs")
		return nil, nil, limits.ErrActorExceededMaxQueuedJobs
	}

	// job.RunOptions
	if !builder.job.HasRunOptions() {
		builder.job.RunOptions = builder.runOptions
		if builder.runOptionsHook != nil {
			builder.job.RunOptions = builder.runOptionsHook(builder.job)
		}
	}

	if builder.job.Model == "" {
		model, err := builder.service.DetermineModel(ctx, builder.model, builder.job)
		if err != nil {
			switch {
			case errors.Is(err, ErrNoModelAvailable):
				builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("no models available for user")
				return nil, nil, goerrors.Errorf("no models available for user: %w", err)
			case errors.Is(err, ErrModelNotFound):
				builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("requested model not available for user", kvp.String("model", builder.model))
				return nil, nil, goerrors.Errorf("no valid model found for user: %w", err)
			}
			return nil, nil, goerrors.Errorf("failed to determine model for job: %w", err)
		}

		builder.job.Model = model
		builder.service.obsv.LoggerWithTelemetry(ctx).Info("determined model for job", kvp.String("model", builder.job.Model))
	} else {
		builder.service.obsv.LoggerWithTelemetry(ctx).Info("using pre-set model for job, skipping DetermineModel", kvp.String("model", builder.job.Model))
	}

	// job.EnvironmentFeatures
	if !builder.job.HasFeatures() {
		builder.job.Features = builder.features
		if builder.featuresBuilder != nil {
			builder.job.Features = builder.featuresBuilder(ctx, builder.job)
		}
	}

	// comment IDs (must come before problem statement)
	if len(builder.commentIDs) != 0 {
		builder.job.CommentIDs = append(builder.job.CommentIDs, builder.commentIDs...)
		// remove duplicates and unused capacity
		slices.Sort(builder.job.CommentIDs)
		builder.job.CommentIDs = slices.Clip(slices.Compact(builder.job.CommentIDs))
	}

	// review IDs (must come before problem statement)
	if len(builder.reviewIDs) != 0 {
		builder.job.ReviewIDs = append(builder.job.ReviewIDs, builder.reviewIDs...)
		// remove duplicates and unused capacity
		slices.Sort(builder.job.ReviewIDs)
		builder.job.ReviewIDs = slices.Clip(slices.Compact(builder.job.ReviewIDs))
	}

	// problem statement
	// we also support loading an existing job and updating it with a new problem
	// statement, but we need to make sure we don't overwrite an existing problem
	// statement with an empty one
	if builder.problemStatement.Content != "" {
		builder.job.ProblemStatement = builder.problemStatement
	}
	// same for problem statement builder
	if builder.problemStatementBuilder != nil {
		ps, err := builder.problemStatementBuilder(ctx, builder.job)
		if err != nil {
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("problem statement builder returned an error")
			if builder.finalizeUnexecutedJobForError(ctx, nil, err) {
				return nil, nil, &BuilderFinalizedJobError{Err: err}
			}
			return nil, nil, goerrors.Errorf("failed to build problem statement: %w", err)
		}
		builder.job.ProblemStatement = ps
	}

	// job.CustomAgent
	if !builder.job.HasCustomAgent() {
		sa := builder.customAgent
		if sa != nil {
			builder.job.CustomAgent = sa.ToDB()
		}
	}

	if builder.job.RequestStartedAt == 0 && builder.requestStartedAt != nil {
		builder.job.RequestStartedAt = builder.requestStartedAt.Unix()
	}

	// Set the Agent ID on the job if the job doesn't already have one
	// and the builder has one configured.
	// This scenario is prevalent when we create jobs in async mode, where
	// it gets saved to the DB, then when we hydrate and "rebuild" the job later
	// the job may already have an agent id, and we want to preserve that rather than overwrite it.
	if builder.job.AgentID == 0 && builder.agentID != 0 {
		builder.job.AgentID = builder.agentID
	}

	agent, err := builder.service.appProvider.FindByID(builder.job.AgentID)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to find agent by ID: %w", err)
	}

	// job.EventType, job.EventURL, job.EventIdentifiers, job.EventContent
	if builder.event != nil {
		builder.job.EventType = builder.event.Type
		builder.job.EventURL = builder.event.URL
		builder.job.EventIdentifiers = builder.event.Identifiers
		builder.job.EventContent = builder.event.Content
		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// Details for creating new resources. We first determine if we should create
	// a session, branch, and/or pull request based on the job state and builder
	// configuration, then we create them. The following three variables will ONLY
	// be non-nil if we need to create the corresponding resource.
	var newSession *session
	var newBranch *branch
	var newPullRequest *pullRequest

	// Determine if we need a job title. This is true when:
	// - We're creating a new sync session (UseAsyncSessions=false and no session yet), OR
	// - We're using async sessions (the title will be sent via Hydro event), OR
	// - AI name generation is explicitly enabled (to regenerate placeholder names)
	needsJobTitle := builder.useAINameGen || (builder.createSession && (builder.job.UseAsyncSessions || !builder.job.HasSession()))

	// Set default job title if needed (may be overridden by AI generation later)
	if needsJobTitle && builder.job.Title == "" {
		switch builder.job.Action {
		case jobs.AgentActionFix:
			builder.job.Title = "Initial implementation"
		case jobs.AgentActionFixPRComment:
			builder.job.Title = fmt.Sprintf("Review from @%s", builder.job.ActorDisplayLogin)
		default:
			builder.job.Title = "Initial session"
		}
	}

	// determine if we need to create a session, if so we set a value for newSession
	// When UseAsyncSessions is true, the runtime handles session management.
	if !builder.job.UseAsyncSessions && !builder.job.HasSession() && builder.createSession {
		newSession = &session{
			Name: builder.job.Title,
		}
	}

	// if no branch name suffix provided, default to <action>-<job id>
	defaultBranchNameSuffix := fmt.Sprintf("%s-%s", builder.job.Action, builder.job.ID)

	// determine if we need to create a new branch, if so we set a value for
	// newBranch independent of what the PR flow determined
	if !builder.job.HasBranch() && builder.job.RequiresBranch() && !builder.job.RequiresPullRequest() && !builder.withoutCreatingFeatures {
		newBranch = &branch{
			BaseCommit: builder.job.Features.Branch.BaseRef,
			NameSuffix: builder.job.Features.Branch.Name,
		}
		// if no branch name suffix provided, default to <action>-<job id>
		if newBranch.NameSuffix == "" {
			newBranch.NameSuffix = defaultBranchNameSuffix
		}
	}

	// determine if we need to create a new pull request, if so we set a value for
	// BOTH newBranch and newPullRequest (since a PR requires a branch)
	newPullRequest = builder.determinePullRequestCreation(defaultBranchNameSuffix)
	if newBranch == nil && newPullRequest != nil && newPullRequest.Branch.NameSuffix != "" {
		newBranch = &newPullRequest.Branch
	}

	// Generate AI names when we need a job title, branch, or PR, and AI name generation is enabled
	generateNames := (needsJobTitle || newBranch != nil || newPullRequest != nil) &&
		builder.job.ProblemStatement.Content != "" &&
		builder.useAINameGen &&
		builder.service.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAINameGeneration, builder.job)

	var jd *aigen.JobData

	// If we're creating a PR or a session, AI-generate names for them if enabled.
	if generateNames {
		namegen := aigen.NewNameGenerator(builder.service.obsv, builder.service.capi, builder.service.ffs)
		jd, err = namegen.GenerateJobData(ctx, builder.job)
		if err != nil {
			builder.service.obsv.LogAndReportError(ctx, err, "failed to generate job data with AI")
		}
	}

	if jd != nil {
		// Override the title with AI-generated session name, and sync to newSession if needed
		if needsJobTitle && jd.SessionName != "" {
			builder.job.Title = jd.SessionName

			if newSession != nil {
				newSession.Name = jd.SessionName
			}
		}

		// If we were going to create a branch, override the suffix with the AI-generated name
		// ONLY if no explicit branch name suffix was provided by the user.
		if newBranch != nil && jd.BranchName != "" && (newBranch.NameSuffix == "" || newBranch.NameSuffix == defaultBranchNameSuffix) {
			newBranch.NameSuffix = jd.BranchName
		}

		// If we were going to create a PR, override the title/branch with the AI-generated title.
		if newPullRequest != nil && jd.PullRequestTitle != "" {
			newPullRequest.Title = "[WIP] " + jd.PullRequestTitle
		}
	}

	// Initialize session client early if we need to create or update a session
	var sessionClient capi.SessionClient
	needsSessionUpdate := !builder.job.UseAsyncSessions && builder.job.HasSession() && builder.useAINameGen && jd != nil && jd.SessionName != ""
	if !builder.job.UseAsyncSessions && (newSession != nil || needsSessionUpdate) {
		sessionClient, err = builder.service.GetSessionClient(ctx, builder.agentID, builder.job)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to get session client: %w", err)
		}
	}

	// create branch
	//nolint:nestif // Nested ifs are necessary for the flow of creating branches
	if newBranch != nil {
		// job must have a base commit to create the branch and PR
		if builder.job.BaseCommit == "" && newBranch.BaseCommit == "" {
			return nil, nil, goerrors.New("no base commit provided for branch")
		}
		if builder.job.BaseCommit == "" {
			builder.job.BaseCommit = newBranch.BaseCommit
		}

		branchNameSuffix := newBranch.NameSuffix
		if branchNameSuffix == "" {
			branchNameSuffix = defaultBranchNameSuffix
		}

		// We could have a slight performance improvement here as we probably only
		// will use one of these names on the hot path.  However, generating multiple
		// names upfront comes at only about a 3ms cost and makes the following code
		// simpler
		names := builder.service.GeneratePotentialBranchNames(ctx, agent.BranchPrefix(), branchNameSuffix, uint64(builder.job.RepoID))
		if len(names) == 0 {
			return nil, nil, goerrors.New("unable to generate any potential branch names")
		}

		// uses job.BranchName set above
		commitOID, err := builder.service.CreateEmptyCommit(ctx, gh, builder.job)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to create empty commit: %w", err)
		}

		branchCreated := false
		var rulesError *RulesViolationError
		for _, name := range names {
			builder.job.BranchName = name
			builder.service.updateRequestContextJob(ctx, builder.job)

			// Check repository rules before creating the branch
			// TODO (Houndie):  There's a bit of performance improvement that can be done
			// inside here:  In the case of using multiple branches, we're quering for a
			// few rules multiple times (the existence of a branch with the agent prefix,
			// and any repository rules.  However, we do need to make a separate call for
			// branch protection rules on each branch. In the future, we might consider
			// either breaking apart these checks, or creating an internal twirp call to
			// check branch protection rules on multiple branches at once...but
			// theoretically this loop often only iterate once, leaving this a non issue
			// for the hot path
			rulesResult := builder.service.CheckRules(ctx, gh, agent, builder.job, builder.repo.GetOwner().GetLogin(), builder.repo.GetName(), builder.job.BranchName)
			if len(rulesResult.Rules) > 0 {
				if builder.branchRuleViolationHook != nil {
					err = builder.branchRuleViolationHook(ctx, gh, builder.actor.Login, builder.assignment, rulesResult)
					// if the hook returns an error, we stop processing and return it
					if err != nil {
						builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("branch rule violation hook returned an error")
						return nil, nil, err
					}
				}
				// Log and return error if no hook is provided
				rulesError = &RulesViolationError{CheckRulesResult: rulesResult}
				builder.service.obsv.LoggerWithTelemetry(ctx).WithError(rulesError).Error("repository rules violation")
				continue
			}

			// uses job.BranchName set above
			err = builder.service.CreateBranch(ctx, gh, builder.job, commitOID)
			if err == nil {
				branchCreated = true
				break
			}

			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error(fmt.Sprintf("failed to create branch %s, trying another", name))
		}

		if !branchCreated {
			err := goerrors.New("unable to create branch from any options")
			if rulesError != nil {
				// If we encountered a rules violation error at any point, we should be
				// reporting this back to the client.
				err = rulesError
			}

			if builder.finalizeUnexecutedJobForError(ctx, sessionClient, err) {
				return nil, nil, &BuilderFinalizedJobError{Err: err}
			}

			return nil, nil, err
		}

		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// create pull request
	//nolint:nestif // Nested ifs are necessary for the flow of creating pull requests
	if newPullRequest != nil {
		// this should never happen since we check above, but just in case
		if builder.job.BaseCommit == "" || builder.job.BranchName == "" {
			return nil, nil, goerrors.New("no base commit or branch name provided for pull request")
		}

		body := newPullRequest.Body
		if body == "" {
			// Ensure that the PR body has at least the default prefix
			body = PRBodyPrefix
		}

		// add tip to PR body if applicable and the job is using the Copilot app
		if builder.service.appProvider.IsCopilotApp(builder.job.AgentID) {
			tip := tips.GetRandomTipForJob(ctx, builder.service.ffs, builder.job, builder.repo)
			if tip != "" {
				tip = tips.PullRequestBodyTipSeparator + tip
				// only add the tip if it doesn't make the body too long
				if totalLength(body, tip) < github.MaxPullRequestBodyLength {
					body += tip
				}
			}
		}

		// sets job.PullRequestID and job.PullRequestNumber if successful
		err = builder.service.OpenPullRequest(ctx, builder.service.twirp.SweagentdAPI(), builder.assignment, builder.job, newPullRequest.Title, body)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to create pull request: %w", err)
		}
		// add labels to PR if specified
		if builder.features.PullRequest != nil && len(builder.features.PullRequest.Labels) > 0 {
			err := gh.AddLabelsToIssueOrPR(ctx, builder.repo.Owner.GetLogin(), builder.repo.GetName(), builder.job.PullRequestNumber, builder.features.PullRequest.Labels)
			if err != nil {
				return nil, nil, goerrors.Errorf("failed to add labels to issue: %w", err)
			}
		}

		// we modified the assignment by adding a PR, so we need to save it
		saveAssignment = true

		// if we just created a session, we didn't have the pull request ID
		// available when we created it. we also could have loaded a job built
		// earlier with a session but no pull request. either way, we now need
		// to update the session to link it to the pull request we just created.
		// When UseAsyncSessions is true, sessions are managed by an upstream service.
		if !builder.job.UseAsyncSessions && builder.job.HasSession() {
			builder.service.obsv.LoggerWithTelemetry(ctx).Info("linking pull request to session")

			resourceType := capi.ResourceTypePullRequest
			sessionUpdate := capi.SessionUpdate{
				ResourceType: &resourceType,
				ResourceID:   builder.job.PullRequestID,
			}
			// Also update session name if AI name generation produced a new title
			if needsSessionUpdate {
				sessionUpdate.Name = jd.SessionName
				needsSessionUpdate = false // Mark as handled
			}
			err = builder.service.updateSession(ctx, sessionClient, builder.job, sessionUpdate)
			if err != nil {
				return nil, nil, goerrors.Errorf("failed to link pull request to session: %w", err)
			}
		}

		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// Update session name if AI name generation produced a new title and we haven't updated yet
	// (this handles the case where no PR was created but we still need to update the session name)
	if needsSessionUpdate && sessionClient != nil {
		sessionUpdate := capi.SessionUpdate{
			Name: jd.SessionName,
		}
		err = builder.service.updateSession(ctx, sessionClient, builder.job, sessionUpdate)
		if err != nil {
			builder.service.obsv.LogAndReportError(ctx, err, "failed to update session name")
			// Don't fail the build, just log the error
		}
	}

	// create session after branch/pull request so we persist head/base refs on create
	if newSession != nil {
		// TODO (colbylwilliams): consider returning BuilderFinalizedJobError if
		// session creation fails. For now we'll let it bubble up as a regular
		// error and let the retry logic handle it.
		sessionID, err := builder.service.createSessionForJob(ctx, sessionClient, builder.job, capi.SessionStateQueued, newSession.Name)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to create session: %w", err)
		}
		builder.job.SessionID = sessionID
	}

	// If we didn't create a branch, but we expect to in the future, we still need
	// to check rules to make sure the job can be completed
	//nolint:nestif // Nested ifs are necessary for the flow of creating branches
	if newBranch == nil && !builder.job.HasBranch() && builder.job.RequiresBranch() {
		ruleCheckBranchName := builder.job.ID
		if jd != nil && jd.BranchName != "" {
			ruleCheckBranchName = jd.BranchName
		}
		ruleCheckBranchName = fmt.Sprintf("%s/%s", agent.BranchPrefix(), ruleCheckBranchName)
		rulesResult := builder.service.CheckRules(ctx, gh, agent, builder.job, builder.repo.GetOwner().GetLogin(), builder.repo.GetName(), ruleCheckBranchName)
		if len(rulesResult.Rules) > 0 {
			if builder.branchRuleViolationHook != nil {
				err = builder.branchRuleViolationHook(ctx, gh, builder.actor.Login, builder.assignment, rulesResult)
				// if the hook returns an error, we stop processing and return it
				if err != nil {
					builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("branch rule violation hook returned an error")
					return nil, nil, err
				}
			}
			// Log and return error if no hook is provided
			rulesError := &RulesViolationError{CheckRulesResult: rulesResult}
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(rulesError).Error("repository rules violation")
			if builder.finalizeUnexecutedJobForError(ctx, sessionClient, rulesError) {
				return nil, nil, &BuilderFinalizedJobError{Err: rulesError}
			}
			return nil, nil, rulesError
		}
	}

	// onboarding (must come after pull request is created)
	if !builder.job.HasOnboardingComment() && builder.onboarding && builder.job.PullRequestNumber != 0 {
		// Substitute the onboarding tip if the feature flag is enabled and the magic string is present.
		builder.job.ProblemStatement.Content = onboarding.SubstituteOnboardingTipIfEnabled(ctx, builder.service.ffs, builder.job, builder.job.ProblemStatement.Content)

		onboardingComment, err := onboarding.CreateOnboardingCommentIfNeeded(ctx, builder.service.ffs, builder.service.store, gh, builder.job, builder.repo)
		if err != nil {
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to create onboarding comment")
		} else if onboardingComment != nil {
			builder.job.OnboardingCommentID = *onboardingComment.ID
		}
	}

	builder.service.updateRequestContextJob(ctx, builder.job)

	// experiments (today this needs to come after labels and pull request are set)
	// only set experiments if they are not already set on the assignment, as
	// we don't want to overwrite existing experiment assignments
	if builder.assignment.Experiments == nil && builder.experiments {
		err := builder.service.SetExperimentAssignmentsForJob(ctx, experiments.AllExperiments, builder.assignment, builder.job)
		if err != nil {
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to set experiments on new assignment and job")
		}
		saveAssignment = saveAssignment || err == nil
	}

	// If the builder.assignment came from the database, we haven't modified it,
	// and should not try to save it again.
	if saveAssignment {
		// save assignment
		assignment, err := builder.service.store.UpsertAssignment(ctx, builder.assignment)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to save assignment: %w", err)
		}
		builder.assignment = assignment
	}

	// pre-save job hook
	if builder.jobSaveHook != nil {
		builder.jobSaveHook(builder.job)
	}

	// save job
	builder.job, err = builder.service.store.UpsertJob(ctx, builder.job)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to save job: %w", err)
	}
	builder.service.updateRequestContextJob(ctx, builder.job)

	builder.service.obsv.Increment(ctx, "jobs.created", nil)

	builder.built = true

	return builder.assignment, builder.job, nil
}

// finalizeUnexecutedJobForError finalizes a job that was never executed due to
// an expected/known error that occurred during the build process and returns
// true if the error provided can be handled and the job and session were finalized.
func (builder *JobBuilderWithAssignmentAndActor) finalizeUnexecutedJobForError(ctx context.Context, sessionClient capi.SessionClient, e error) bool {
	if builder.job == nil {
		return true // nothing to finalize
	}

	var rulesErr *RulesViolationError
	// TODO (calvinmvrk): uncomment when you add the problem statement too long error handling
	// var problemStatementErr *problemstatement.ErrProblemStatementTooLong
	switch {
	case errors.As(e, &rulesErr):
		// finalize job and session for rules violation
		sessionMessage := fmt.Sprintf("session could not proceed due to repository rules violations: %s", rulesErr.RulesString())
		err := builder.service.finalizeUnexecutedJob(ctx, sessionClient, builder.job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrRulesViolation, sessionMessage))
		if err != nil {
			// log and report but don't override the original error
			builder.service.obsv.LogAndReportError(ctx, err, "failed to finalize unexecuted job for rules violation")
		} else {
			builder.service.obsv.LoggerWithTelemetry(ctx).Info("finalized unexecuted job due to rules violation")
		}
		return true
		// TODO (calvinmvrk): uncomment when you add the problem statement too long error handling
		// case errors.As(e, &problemStatementErr):
		//	// finalize job and session for problem statement too long
		//	sessionMessage := fmt.Sprintf("session could not proceed because the problem statement is too long: %s", problemStatementErr.Error())
		//	err := builder.service.finalizeUnexecutedJob(ctx, sessionClient, builder.job, jobs.JobStatusFailed, "problem_statement_too_long", sessionMessage)
		//	if err != nil {
		//		// log and report but don't override the original error
		//		builder.service.obsv.LogAndReportError(ctx, err, "failed to finalize unexecuted job for problem statement too long")
		//	} else {
		//		builder.service.obsv.LoggerWithTelemetry(ctx).Info("finalized unexecuted job due to problem statement too long")
		//	}
		//	return true
	default:
		// unknown error type, cannot finalize
		return false
	}
}

// totalLength returns the total length of all provided strings combined.
func totalLength(parts ...string) int {
	total := 0
	for _, part := range parts {
		total += len(part)
	}
	return total
}

// resolveActorDisplayLogin gets the DisplayLogin field of the JobActor by
// resolving the user ID to a display login using the GitHub Sweagentd service.
//
// This method is written in such a way that it should *never* error outside of
// a Proxima environment. The behavior of this method outside of a Proxima
// environment is only to return the value for Login.
func (s *Service) resolveActorDisplayLogin(ctx context.Context, actor *jobs.JobActor) (string, error) {
	if actor.DisplayLogin != "" {
		return actor.DisplayLogin, nil
	}
	resolvedLogin, err := githubtwirp.ResolveDisplayLogin(ctx, s.twirp, s.obsv, s.ffs, uint64(actor.ID), actor.Login)
	if err != nil {
		return "", goerrors.Errorf("failed to resolve display login: %w", err)
	}
	return resolvedLogin, nil
}
