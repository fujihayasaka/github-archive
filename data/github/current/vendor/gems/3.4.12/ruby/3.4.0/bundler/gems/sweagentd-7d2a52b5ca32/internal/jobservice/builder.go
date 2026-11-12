package jobservice

import (
	"context"
	"errors"
	"fmt"
	"slices"

	"github.com/github/sweagentd/internal/aigen"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	limits "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/onboarding"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/tips"
)

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

type JobBuilderOption func(*JobBuilder)

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
	assignmentSaveHook         func(*jobs.Assignment)

	jobInitHook func(*jobs.Job)
	jobSaveHook func(*jobs.Job)

	event *Event

	runOptions     jobs.RunOptions
	runOptionsHook func(*jobs.Job) jobs.RunOptions

	createSession bool
	sessionName   string

	commentIDs []int64
	reviewIDs  []int64

	features        jobs.EnvironmentFeatures
	featuresBuilder FeaturesBuilderFunc

	withoutCreatingFeatures bool

	branchRuleViolationHook BranchRuleViolationHookFunc

	labelable github.Labelable

	pullRequestLabels []string

	problemStatement        jobs.ProblemStatement
	problemStatementBuilder ProblemStatementBuilderFunc

	customAgent        *customagent.Agent
	customAgentBuilder CustomAgentBuilderFunc

	onboarding bool

	experiments bool
}

type JobBuilderWithAssignmentAndActor struct {
	*JobBuilderWithAssignment
}

type JobBuilderWithAssignment struct {
	*JobBuilder
}

/** Assignment **/

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
func (builder *JobBuilder) WithNewAssignment(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, resources ...jobs.AssignmentResource) *JobBuilderWithAssignment {
	builder.assignment = jobs.NewAssignment(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, resources...)
	return &JobBuilderWithAssignment{builder}
}

// WithNewAssignmentWithCustomAgent creates and sets a new assignment with a custom agent for the job
func (builder *JobBuilder) WithNewAssignmentWithCustomAgent(ownerID, repoID int64, ownerNodeID, repoNodeID, ownerName, repoName string, agent sweagentd.CustomAgent, resources ...jobs.AssignmentResource) *JobBuilderWithAssignment {
	builder.assignment = jobs.NewAssignmentWithCustomAgent(ownerID, repoID, ownerNodeID, repoNodeID, ownerName, repoName, agent.ToDB(), resources...)
	return &JobBuilderWithAssignment{builder}
}

// WithSaveAssignmentHook sets a hook that is called immediately before saving
// the assignment to the database.
func (builder *JobBuilderWithAssignment) WithSaveAssignmentHook(hook func(*jobs.Assignment)) *JobBuilderWithAssignment {
	builder.assignmentSaveHook = hook
	return builder
}

/** Actor **/

// WithActor sets the actor (user) to associate with the job.
func (builder *JobBuilderWithAssignment) WithActor(id int64, login, displayLogin, trackingID string) *JobBuilderWithAssignmentAndActor {
	return builder.WithJobActor(jobs.JobActor{
		ID:           id,
		Login:        login,
		DisplayLogin: displayLogin,
		TrackingID:   trackingID,
	})
}

func (builder *JobBuilderWithAssignment) WithJobActor(actor jobs.JobActor) *JobBuilderWithAssignmentAndActor {
	builder.actor = actor
	return &JobBuilderWithAssignmentAndActor{builder}
}

/** Job **/

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

/** Event Details **/

// WithEvent sets the event details to associate with the job.
func (builder *JobBuilderWithAssignmentAndActor) WithEvent(event Event) *JobBuilderWithAssignmentAndActor {
	builder.event = &event
	return builder
}

/** Run Options **/

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

/** Problem Statement **/

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

/** Comment and Review IDs **/

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

/** Labels **/

// WithLabelsFrom sets the labelable entity (issue, PR, etc.) to use for extracting
// labels to associate with the job.
func (builder *JobBuilderWithAssignmentAndActor) WithLabelsFrom(labelable github.Labelable) *JobBuilderWithAssignmentAndActor {
	builder.labelable = labelable
	return builder
}

/** Environment Features **/

// WithFeatures sets the environment features to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithFeatures(features jobs.EnvironmentFeatures) *JobBuilderWithAssignmentAndActor {
	builder.features = features
	return builder
}

// FeaturesBuilderFunc is a function that builds environment features based
// on the context and job.
type FeaturesBuilderFunc func(ctx context.Context, job *jobs.Job) jobs.EnvironmentFeatures

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

/** Session **/

// WithNewSession indicates that a new session should be created for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithNewSession() *JobBuilderWithAssignmentAndActor {
	builder.createSession = true
	return builder
}

/** Custom Agent **/

// WithCustomAgent sets a specific custom agent to use for the job.
func (builder *JobBuilderWithAssignmentAndActor) WithCustomAgent(agent *customagent.Agent) *JobBuilderWithAssignmentAndActor {
	builder.customAgent = agent
	return builder
}

// CustomAgentBuilderFunc is a function that builds a custom agent based on the context,
// GitHub client, repository owner and name, and label metadata.
type CustomAgentBuilderFunc func(ctx context.Context, gh github.ClientInterface, owner, repo string, lm sweagentd.LabelMetadata) (*customagent.Agent, error)

// WithCustomAgentBuilder sets a builder function that is called to determine the
// custom agent to use for the job based on the job details and labels.
func (builder *JobBuilderWithAssignmentAndActor) WithCustomAgentBuilder(hook CustomAgentBuilderFunc) *JobBuilderWithAssignmentAndActor {
	builder.customAgentBuilder = hook
	return builder
}

/** Onboarding **/

// WithOnboarding indicates that onboarding features should be applied to the job.
func (builder *JobBuilderWithAssignmentAndActor) WithOnboarding() *JobBuilderWithAssignmentAndActor {
	builder.onboarding = true
	return builder
}

/** Experiments **/

func (builder *JobBuilderWithAssignmentAndActor) WithExperiments() *JobBuilderWithAssignmentAndActor {
	builder.experiments = true
	return builder
}

// NewJobBuilder creates a new JobBuilder with the given action and default branch provider.
func (s *Service) NewJobBuilder(action jobs.AgentAction, baseCommit string) *JobBuilder {
	builder := &JobBuilder{
		service:       s,
		defaultBranch: baseCommit,
		action:        action,
	}
	return builder
}

// JobBuilderForJob creates a JobBuilder initialized with the given assignment and job.
func (s *Service) JobBuilderForJob(assignment *jobs.Assignment, job *jobs.Job) *JobBuilderWithAssignmentAndActor {
	builder := &JobBuilder{
		service:    s,
		action:     job.Action,
		assignment: assignment,
		job:        job,
		actor: jobs.JobActor{
			ID:           job.ActorID,
			Login:        job.ActorLogin,
			DisplayLogin: job.ActorDisplayLogin,
			TrackingID:   job.ActorAnalyticsTrackingID,
		},
	}
	return &JobBuilderWithAssignmentAndActor{&JobBuilderWithAssignment{builder}}
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

// Build constructs the job and resources based on the provided configuration and saves it to the database.
func (builder *JobBuilderWithAssignmentAndActor) Build(ctx context.Context, gh github.ClientInterface) (*jobs.Assignment, *jobs.Job, error) {
	ctx, span := builder.service.obsv.Tracer.Start(ctx, "jobservice.BuildJob")
	defer span.End()

	if builder.assignment == nil {
		// existing assignment lookup
		if builder.assignmentLookupByID != nil {
			assignment, err := builder.service.store.GetAssignment(ctx,
				builder.assignmentLookupByID.OwnerID,
				builder.assignmentLookupByID.RepoID,
				builder.assignmentLookupByID.AssignmentID,
			)
			if err != nil {
				return nil, nil, fmt.Errorf("failed to get assignment by ID: %w", err)
			}
			if assignment == nil {
				return nil, nil, fmt.Errorf("no assignment found with ID")
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
				return nil, nil, fmt.Errorf("failed to get assignment for resource: %w", err)
			}
			if assignment == nil {
				return nil, nil, fmt.Errorf("no assignment found for resource")
			}
			builder.assignment = assignment
		}
	}

	if builder.assignment == nil {
		return nil, nil, fmt.Errorf("no assignment provided")
	}

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
			return nil, nil, fmt.Errorf("failed to build problem statement: %w", err)
		}
		builder.job.ProblemStatement = ps
	}

	// labels
	var labelMetadata sweagentd.LabelMetadata
	if builder.labelable != nil {
		labelMetadata = builder.service.LabelMetadataForJob(ctx, builder.job, builder.labelable)

		// Only apply copilot labels to any resulting PR when a labelable is provided.
		builder.pullRequestLabels = labelMetadata.CopilotLabels
	} else if builder.job.RequiresPullRequest() && len(builder.job.Features.PullRequest.Labels) != 0 {
		labelMetadata = labelMetadataWithChecks(ctx, builder.service.ffs, builder.job, builder.job.Features.PullRequest.Labels)
		// If explicit labels are provided, we'll apply all of them to the resulting PR.
		builder.pullRequestLabels = builder.job.Features.PullRequest.Labels
	}

	// job.CustomAgent
	if !builder.job.HasCustomAgent() {
		sa := builder.customAgent
		if builder.customAgentBuilder != nil {
			var err error
			sa, err = builder.customAgentBuilder(ctx, gh, builder.assignment.RepoOwner, builder.assignment.RepoName, labelMetadata)
			if err != nil {
				builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("custom agent builder returned an error")
				return nil, nil, fmt.Errorf("failed to build custom agent: %w", err)
			}
		}
		if sa != nil {
			builder.job.CustomAgent = sa.ToDB()
		}
	}

	// job.EventType, job.EventURL, job.EventIdentifiers, job.EventContent
	if builder.event != nil {
		builder.job.EventType = builder.event.Type
		builder.job.EventURL = builder.event.URL
		builder.job.EventIdentifiers = builder.event.Identifiers
		builder.job.EventContent = builder.event.Content
		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	var err error

	// Details for creating new resources. We first determine if we should create
	// a session, branch, and/or pull request based on the job state and builder
	// configuration, then we create them. The following three variables will ONLY
	// be non-nil if we need to create the corresponding resource.
	var newSession *session
	var newBranch *branch
	var newPullRequest *pullRequest

	// determine if we need to create a session, if so we set a value for newSession
	if !builder.job.HasSession() && builder.createSession {
		newSession = &session{
			Name: builder.sessionName,
		}
		if newSession.Name == "" {
			if builder.job.Action == jobs.AgentActionFix {
				newSession.Name = "Initial implementation"
			} else {
				newSession.Name = fmt.Sprintf("Review from @%s", builder.job.ActorDisplayLogin)
			}
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

	generateNames := false
	if (newSession != nil || newBranch != nil || newPullRequest != nil) && builder.job.ProblemStatement.Content != "" {
		generateNames = builder.service.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAINameGeneration, builder.job)
	}
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
		// If we were going to create a session, override the name with the AI-generated name.
		if newSession != nil && jd.SessionName != "" {
			newSession.Name = jd.SessionName
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

	// create session
	if newSession != nil {
		sessionID, err := builder.service.createSessionForJob(ctx, builder.job, capi.SessionStateQueued, newSession.Name)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to create session: %w", err)
		}
		builder.job.SessionID = sessionID

		builder.service.updateRequestContextJob(ctx, builder.job)
		builder.service.addRequestCtxSessionFromJob(ctx, builder.job)
	}

	// create branch
	if newBranch != nil {
		// job must have a base commit to create the branch and PR
		if builder.job.BaseCommit == "" && newBranch.BaseCommit == "" {
			return nil, nil, errors.New("no base commit provided for branch")
		}
		if builder.job.BaseCommit == "" {
			builder.job.BaseCommit = newBranch.BaseCommit
		}

		branchNameSuffix := newBranch.NameSuffix
		if branchNameSuffix == "" {
			branchNameSuffix = defaultBranchNameSuffix
		}

		// sets job.BranchName to a unique branch name
		err = builder.service.GenerateBranchName(ctx, gh, builder.job, branchNameSuffix)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to generate branch name: %w", err)
		}

		// Check repository rules before creating the branch
		rulesResult := builder.service.CheckRules(ctx, gh, builder.job, builder.job.BranchName)
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
			return nil, nil, rulesError
		}

		// uses job.BranchName set above
		err = builder.service.CreateBranch(ctx, gh, builder.job)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to create branch: %w", err)
		}

		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// create pull request
	if newPullRequest != nil {
		// this should never happen since we check above, but just in case
		if builder.job.BaseCommit == "" || builder.job.BranchName == "" {
			return nil, nil, errors.New("no base commit or branch name provided for pull request")
		}

		body := newPullRequest.Body

		// add tip to PR body if applicable
		tip := tips.GetRandomTipForJob(ctx, builder.service.ffs, builder.job)
		if tip != "" {
			tip = tips.PullRequestBodyTipSeparator + tip
			// only add the tip if it doesn't make the body too long
			if totalLength(body, tip) < github.MaxPullRequestBodyLength {
				body += tip
			}
		}

		// sets job.PullRequestID and job.PullRequestNumber if successful
		err = builder.service.OpenPullRequest(ctx, builder.service.twirp.SweagentdAPI(), builder.assignment, builder.job, newPullRequest.Title, body)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to create pull request: %w", err)
		}

		// if we just created a session, we didn't have the pull request ID
		// available when we created it. we also could have loaded a job built
		// earlier with a session but no pull request. either way, we now need
		// to update the session to link it to the pull request we just created.
		if builder.job.HasSession() {
			builder.service.obsv.LoggerWithTelemetry(ctx).Info("linking pull request to session")
			resourceType := capi.ResourceTypePullRequest
			sessionUpdate := capi.SessionUpdate{
				ResourceType: &resourceType,
				ResourceID:   builder.job.PullRequestID,
			}
			err = builder.service.updateSession(ctx, nil, builder.job, sessionUpdate)
			if err != nil {
				return nil, nil, fmt.Errorf("failed to link pull request to session: %w", err)
			}
		}

		if len(builder.pullRequestLabels) > 0 {
			err := gh.AddLabelsToIssueOrPR(ctx, builder.job.RepoOwner, builder.job.RepoName, builder.job.PullRequestNumber, builder.pullRequestLabels)
			if err != nil {
				return nil, nil, fmt.Errorf("failed to add labels to issue: %w", err)
			}
		}

		builder.service.updateRequestContextJob(ctx, builder.job)
	}

	// If we didn't create a branch, but we expect to in the future, we still need
	// to check rules to make sure the job can be completed
	if newBranch == nil && !builder.job.HasBranch() && builder.job.RequiresBranch() {
		ruleCheckBranchName := builder.job.ID
		if jd != nil && jd.BranchName != "" {
			ruleCheckBranchName = jd.BranchName
		}
		ruleCheckBranchName = fmt.Sprintf("%s/%s", github.CopilotBranchPrefix, ruleCheckBranchName)
		rulesResult := builder.service.CheckRules(ctx, gh, builder.job, ruleCheckBranchName)
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
			return nil, nil, rulesError
		}
	}

	// onboarding (must come after pull request is created)
	if !builder.job.HasOnboardingComment() && builder.onboarding && builder.job.PullRequestNumber != 0 {
		// Substitute the onboarding tip if the feature flag is enabled and the magic string is present.
		builder.job.ProblemStatement.Content = onboarding.SubstituteOnboardingTipIfEnabled(ctx, builder.service.ffs, builder.job, builder.job.ProblemStatement.Content)

		onboardingComment, err := onboarding.CreateOnboardingCommentIfNeeded(ctx, builder.service.ffs, builder.service.store, gh, builder.job)
		if err != nil {
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to create onboarding comment")
		} else if onboardingComment != nil {
			builder.job.OnboardingCommentID = *onboardingComment.ID
		}
	}

	builder.service.updateRequestContextJob(ctx, builder.job)

	// experiments (today this needs to come after labels and pull request are set)
	if builder.experiments {
		if err := builder.service.SetExperimentAssignmentsForJob(ctx, experiments.AllExperiments, builder.assignment, builder.job); err != nil {
			builder.service.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to set experiments on new assignment and job")
		}
	}

	// determine model, if not already set. must come after labels and experiments are set
	if builder.job.Model == "" {
		builder.job.Model = determineModel(ctx, builder.service.obsv, builder.service.ffs, builder.service.twirp, builder.job, labelMetadata)
	}

	// pre-save assignment hook
	if builder.assignmentSaveHook != nil {
		builder.assignmentSaveHook(builder.assignment)
	}

	// save assignment
	assignment, err := builder.service.store.UpsertAssignment(ctx, builder.assignment)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to save assignment: %w", err)
	}
	builder.assignment = assignment

	// pre-save job hook
	if builder.jobSaveHook != nil {
		builder.jobSaveHook(builder.job)
	}

	// save job
	builder.job, err = builder.service.store.UpsertJob(ctx, builder.job)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to save job: %w", err)
	}
	builder.service.updateRequestContextJob(ctx, builder.job)

	builder.built = true

	return builder.assignment, builder.job, nil
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
		return "", fmt.Errorf("failed to resolve display login: %w", err)
	}
	return resolvedLogin, nil
}
