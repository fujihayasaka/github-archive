package github

import (
	"context"
	"net/http"
	"time"

	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/haswaitedforrep"
)

const mutationCreateCheckRun = `mutation CreateCheckRun($create: CreateCheckRunInput!) {
	createCheckRun(input: $create) {
		checkRun {
			id
			databaseId
			checkSuite {
				id
				databaseId
			}
		}
	}
}`

const mutationUpdateCheckRun = `mutation UpdateCheckRun($update: UpdateCheckRunInput!) {
	updateCheckRun(input: $update) {
		checkRun {
			id
			databaseId
			checkSuite {
				id
				databaseId
			}
		}
	}
}`

// CreateCheckSuiteRequest represents the request creating a check suite
type CreateCheckSuiteRequest struct {
	// Id of the work flow execution
	WorkflowExecutionID types.WorkflowExecutionID
	// The Node ID of the repository.
	RepositoryID types.GlobalID
	// The SHA of the head commit.
	HeadSHA types.CommitSha
	// The ref of the head commit, usually a branch or tag.
	HeadRef types.GitRef
	// The Node ID of the head repository (different to RepositoryID if the HeadSHA is from a forked repo).
	HeadRepositoryID types.GlobalID
	// The Node ID of the creator.
	CreatorID types.GlobalID
	// Any annotations the check suite can include.
	Annotations []CheckSuiteAnnotation

	// Should this CheckSuite be rerunnable?
	Rerequestable bool

	// Should this CheckSuite have explicit completion enabled?
	ExplicitCompletion bool

	// The workflow file full path
	WorkflowFilePath string

	// The workflow name, if different than normal (used in a dynamic workflow run)
	WorkflowName string

	// The parsed workflow execution graph as a json string
	WorkflowExecutionGraph string

	EventName   string
	EventAction string
	Name        string

	TriggerID types.GlobalID

	// The conclusion if when the conclusion of the run is known (either in
	// a start error, or we're told by the backend)
	Conclusion string

	// Decides how to display a check suite in the GitHub UI.
	// Maps to one of `DEFAULT`, `VISIBLE`, `HIDDEN`
	Visibility githubv4.CheckSuiteVisibility

	// A JSON blob of the workflows referenced in this run
	ReferencedWorkflows string

	// The checkout SHA of the workflow file for a required workflow execution.
	// Will be empty for non required workflows
	WorkflowFileCheckoutSHA types.CommitSha

	// The fully qualified ref of the workflow file for a required workflow execution.
	WorkflowFileRef types.GitRef

	// The tree ID of the head SHA
	WorkflowRunTreeID types.CommitSha
}

// CreateCheckSuiteResponse represents the response to creating a check suite
type CreateCheckSuiteResponse struct {
	// A CheckSuite IDPar, if one was created as a result of the invocation.
	CheckSuiteIDPair types.IDPair
	WorkflowRun      *CheckSuiteWorkflowRun
}

type CheckSuiteWorkflowRun struct {
	DatabaseID int64
	RunNumber  int64
}

// ErrorNode is an error response from the GraphQL API.
type ErrorNode struct {
	Path    []githubv4.String
	Message githubv4.String
}

// CreateCheckSuite performs a mutationCreateCheckSuite query
func (c *client) CreateCheckSuite(ctx context.Context, req CreateCheckSuiteRequest) (*CreateCheckSuiteResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var m struct {
		CreateCheckSuite struct {
			CheckSuite struct {
				ID          githubv4.ID
				DatabaseID  githubv4.Int
				WorkflowRun struct {
					DatabaseID githubv4.Int
					RunNumber  githubv4.Int
				}
			}
			Errors []ErrorNode
		} `graphql:"createCheckSuite(input: $input)"`
	}

	creatorIDStr := githubv4.ID(req.CreatorID.String())
	var creatorID *githubv4.ID

	if creatorIDStr != "" {
		creatorID = &creatorIDStr
	}

	var conclusion *githubv4.String
	if req.Conclusion != "" {
		conclusion = githubv4.NewString(githubv4.String(req.Conclusion))
	}

	var visibility *githubv4.CheckSuiteVisibility

	if req.Visibility != "" {
		visibility = &req.Visibility
	}

	input := githubv4.CreateCheckSuiteInput{
		CreatorID:           creatorID,
		ExternalID:          githubv4.NewString(githubv4.String(req.WorkflowExecutionID.String())),
		RepositoryID:        githubv4.NewID(githubv4.ID(req.RepositoryID.String())),
		HeadSha:             githubv4.GitObjectID(req.HeadSHA),
		HeadRepositoryID:    githubv4.NewID(githubv4.ID(req.HeadRepositoryID.String())),
		HeadBranch:          githubv4.NewString(githubv4.String(req.HeadRef.String())),
		Rerequestable:       githubv4.NewBoolean(githubv4.Boolean(req.Rerequestable)),
		Name:                githubv4.NewString(githubv4.String(req.Name)),
		Event:               githubv4.NewString(githubv4.String(req.EventName)),
		Action:              githubv4.NewString(githubv4.String(req.EventAction)),
		CheckRunsRerunnable: githubv4.NewBoolean(githubv4.Boolean(false)),
		ExplicitCompletion:  githubv4.NewBoolean(githubv4.Boolean(req.ExplicitCompletion)),
		WorkflowFilePath:    githubv4.NewString(githubv4.String(req.WorkflowFilePath)),
		WorkflowFileRef:     githubv4.NewString(githubv4.String(req.WorkflowFileRef)),
		Conclusion:          conclusion,
		Visibility:          visibility,
	}

	if req.TriggerID != types.NilGlobalID {
		input.TriggerID = githubv4.NewID(githubv4.ID(req.TriggerID.String()))
	}

	if len(req.Annotations) > 0 {
		input.Annotations = req.GetTypedAnnotations()
	}

	if req.WorkflowExecutionGraph != "" {
		input.WorkflowExecutionGraph = githubv4.NewString(githubv4.String(req.WorkflowExecutionGraph))
	}

	if req.ReferencedWorkflows != "" {
		input.ReferencedWorkflows = githubv4.NewString(githubv4.String(req.ReferencedWorkflows))
	}

	if req.WorkflowFileCheckoutSHA != "" {
		input.WorkflowFileCheckoutSha = githubv4.NewGitObjectID(githubv4.GitObjectID(req.WorkflowFileCheckoutSHA))
	}

	if req.WorkflowName != "" {
		input.WorkflowName = githubv4.NewString(githubv4.String(req.WorkflowName))
	}

	if req.WorkflowRunTreeID != types.CommitShaZeroValue {
		input.WorkflowRunTreeID = githubv4.NewGitObjectID(githubv4.GitObjectID(req.WorkflowRunTreeID.String()))
	}

	optHeaders := http.Header{}

	// if replication lag has been accounted for, set the header to permit replicas
	if haswaitedforrep.FromContext(ctx) {
		optHeaders = c.setPermitReplicasHeader(optHeaders)
	}

	err := c.mutate(ctx, "CreateCheckSuite", &m, input, nil, optHeaders)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	if (m.CreateCheckSuite.CheckSuite.ID == types.NilGlobalID) || (m.CreateCheckSuite.CheckSuite.DatabaseID == 0) {
		return nil, tracing.RecordError(span, errors.New("failed to create a valid check suite"))
	}

	checkSuiteID, ok := m.CreateCheckSuite.CheckSuite.ID.(string)
	if !ok {
		return nil, tracing.RecordError(span, errors.New("check suite id is not a string"))
	}

	res := &CreateCheckSuiteResponse{
		CheckSuiteIDPair: types.IDPair{
			GlobalID:   types.NewGlobalID(ctx, checkSuiteID),
			DatabaseID: int64(m.CreateCheckSuite.CheckSuite.DatabaseID),
		},
		WorkflowRun: &CheckSuiteWorkflowRun{
			DatabaseID: int64(m.CreateCheckSuite.CheckSuite.WorkflowRun.DatabaseID),
			RunNumber:  int64(m.CreateCheckSuite.CheckSuite.WorkflowRun.RunNumber),
		},
	}

	return res, nil
}

func (r *CreateCheckSuiteRequest) GetTypedAnnotations() *[]githubv4.CheckAnnotationData {
	if r.Annotations == nil {
		return nil
	}

	annotations := make([]githubv4.CheckAnnotationData, 0, len(r.Annotations))

	for _, a := range r.Annotations {
		annotations = append(annotations, a.ToTypedAnnotation())
	}

	return &annotations
}

// CheckRunOutput describes the visible output of a CheckRun
type CheckRunOutput struct {
	// A title to provide for this check run.
	Title string `json:"title,omitempty"`
	// The summary of the check run (supports Commonmark).
	Summary string `json:"summary,omitempty"`
	// The details of the check run (supports Commonmark).
	Text string `json:"text,omitempty"`
	// Any annotations the check run can include.
	Annotations []CheckRunAnnotation `json:"annotations,omitempty"`
}

// CheckSuiteAnnotation is an annotation accompanying the CheckSuite.
type CheckSuiteAnnotation struct {
	// Represents an annotation's information level
	AnnotationLevel string `json:"annotationLevel,omitempty"`
	// The location of the annotation
	Location CheckAnnotationRange `json:"location,omitempty"`
	// A short description of the feedback for these lines of code.
	Message string `json:"message,omitempty"`
	// The path of the file to add an annotation to.
	Path string `json:"path,omitempty"`
	// The title that represents the annotation.
	Title string `json:"title,omitempty"`
	// Details about this annotation.
	RawDetails string `json:"rawDetails,omitempty"`
}

func (a *CheckSuiteAnnotation) ToTypedAnnotation() githubv4.CheckAnnotationData {
	var annotationLevel githubv4.CheckAnnotationLevel

	switch a.AnnotationLevel {
	case "FAILURE":
		annotationLevel = githubv4.CheckAnnotationLevelFailure
	case "NOTICE":
		annotationLevel = githubv4.CheckAnnotationLevelNotice
	case "WARNING":
		annotationLevel = githubv4.CheckAnnotationLevelWarning
	}

	return githubv4.CheckAnnotationData{
		Path: githubv4.String(a.Path),
		Location: githubv4.CheckAnnotationRange{
			StartLine:   githubv4.Int(a.Location.StartLine),
			EndLine:     githubv4.Int(a.Location.EndLine),
			StartColumn: githubv4.NewInt(githubv4.Int(a.Location.StartColumn)),
			EndColumn:   githubv4.NewInt(githubv4.Int(a.Location.EndColumn)),
			StepNumber:  githubv4.NewInt(githubv4.Int(a.Location.StepNumber)),
		},
		AnnotationLevel: annotationLevel,
		Message:         githubv4.String(a.Message),
		Title:           githubv4.NewString(githubv4.String(a.Title)),
		RawDetails:      githubv4.NewString(githubv4.String(a.RawDetails)),
	}
}

// CheckRunAnnotation is an annotation accompanying the CheckRun.
type CheckRunAnnotation CheckSuiteAnnotation

// CheckAnnotationRange is the information from a check run analysis to specific lines of code.
type CheckAnnotationRange struct {
	// The starting line of the range.
	StartLine int `json:"startLine,omitempty"`
	// The ending line of the range.
	EndLine int `json:"endLine,omitempty"`
	// The starting column of the range.
	StartColumn int `json:"startColumn,omitempty"`
	// The ending column of the range.
	EndColumn int `json:"endColumn,omitempty"`
	// The step number in logs the annotation was generated from if applicable
	StepNumber int `json:"stepNumber,omitempty"`
}

// CheckRunResponse represents the response to creating or updating a check run
type CheckRunResponse struct {
	// A CheckSuite ID, if one was created as a result of the invocation.
	CheckSuiteIDPair types.IDPair
	// A CheckRun ID, if one was created as a result of the invocation.
	CheckRunIDPair types.IDPair
}

// CreateCheckRunRequest represents the request when creating a check run
//
// Fields not here that exist on the graphql side: detailsUrl, actions, clientMutationId
type CreateCheckRunRequest struct {
	// The Node ID of the repository.
	RepositoryID types.GlobalID `json:"repositoryId,omitempty"`
	// The ID of the CheckSuite to associate this CheckRun with
	CheckSuiteID types.GlobalID `json:"checkSuiteId,omitempty"`
	// A reference for the run on the integrator's system.
	ExternalID string `json:"externalId,omitempty"`
	// The SHA of the head commit.
	HeadSHA types.CommitSha `json:"headSha,omitempty"`
	// The unique name of the check.
	Name string `json:"name,omitempty"`
	// The visible name of the check.
	DisplayName string `json:"displayName,omitempty"`
	// The topological order of the check run within the check suite
	Number int64 `json:"number,omitempty"`
	// The current status, must be "QUEUED", "IN_PROGRESS" or "COMPLETED"
	Status string `json:"status,omitempty"`
	// The conclusion (success or failure). Must be one of:
	// "ACTION_REQUIRED", "TIMED_OUT", "CANCELLED", "FAILURE", "SUCCESS", "NEUTRAL" or "SKIPPED"
	Conclusion string `json:"conclusion,omitempty"`
	// The time that the check run started.
	StartedAt *time.Time `json:"startedAt,omitempty"`
	// The time that the check run finished.
	CompletedAt *time.Time `json:"completedAt,omitempty"`
	// Descriptive details about the run.
	Output *CheckRunOutput `json:"output,omitempty"`
	// Steps this check run will execute.
	Steps []CheckStepData `json:"steps,omitempty"`
	// The completed log information
	CompletedLog *CompletedLog `json:"completedLog,omitempty"`
	// Streaming Log information
	StreamingLog *StreamingLog `json:"streamingLog,omitempty"`
	// Summary URL information
	JobSummary *JobSummary `json:"jobSummary,omitempty"`
	// The job key.
	JobKey string `json:"jobKey,omitempty"`
	// The parent job ID.
	ParentJobID string `json:"parentJobId,omitempty"`
	// Environment Name
	EnvironmentName string `json:"environment,omitempty"`
	// Concurrency group that is blocking the run
	Concurrency *Concurrency `json:"concurrency,omitempty"`
	// Labels
	Labels []string `json:"labels,omitempty"`
	// The ID of the self-hosted runner group, if the workflow_job has been assigned to a runner
	RunnerGroupID int64 `json:"runnerGroupId,omitempty"`
	// The name of the self-hosted runner group, iff the workflow_job has been assigned to a runner
	RunnerGroupName string `json:"runnerGroupName,omitempty"`
	// The ID of the self-hosted runner, if the workflow_job has been assigned to a runner
	RunnerID int64 `json:"runnerId,omitempty"`
	// The name of the self-hosted runner, if the workflow_job has been assigned to a runner
	RunnerName string `json:"runnerName,omitempty"`
	// If the check run is a rerun being created by cloning it from a previous susccessful run
	IsClonedFromPreviousRun bool `json:"isClonedFromPreviousRun,omitempty"`
}

type CheckRunArtifact struct {
	// The full URL to download all files in the artifact.
	SourceURL string `json:"sourceUrl,omitempty"`
	// The name of the artifact.
	Name string `json:"name,omitempty"`
	// The size of the artifact in bytes.
	Size int64 `json:"size"`
	// The datetime the artifact was created.
	CreatedAt *time.Time `json:"createdAt,omitempty"`
	// The datetime the artifact expires.
	ExpiresAt time.Time `json:"expiresAt,omitempty"`
}

type CheckStepData struct {
	// A reference for the check step on the integrator's system.
	ExternalID string `json:"externalId,omitempty"`
	// The name of the step.
	Name string `json:"name,omitempty"`
	// The index of the step. Cannot be set to omitempty, or zero won't marshal
	Number int64 `json:"number"`
	// The completed log information
	CompletedLog *CompletedLog `json:"completedLog,omitempty"`
	// Identifies the date and time when the check step was started.
	StartedAt *time.Time `json:"startedAt,omitempty"`
	// Identifies the date and time when the check step was completed.
	CompletedAt *time.Time `json:"completedAt,omitempty"`
	// The current status of the check step. Must be one of
	// "QUEUED", "IN_PROGRESS", "COMPLETED"
	Status string `json:"status,omitempty"`
	// The conclusion of the check step. Must be one of
	// "ACTION_REQUIRED", "TIMED_OUT", "CANCELLED", "FAILURE", "SUCCESS", "NEUTRAL" or "SKIPPED"
	Conclusion string `json:"conclusion,omitempty"`
}

type CompletedLog struct {
	// The URL where this completed log can be found.
	URL string `json:"url,omitempty"`
	// The number of lines in the log.
	Lines int64 `json:"lines"`
}

type StreamingLog struct {
	// The URL where this streaming log can be found.
	URL string `json:"url,omitempty"`
}

type JobSummary struct {
	// The URL where this job summary can be found.
	URL string `json:"url,omitempty"`
}

type Concurrency struct {
	// The group that is blocking the run or suite
	Group string `json:"group,omitempty"`
	// Reference to blocking resources
	WaitingOnResource *WaitingOnResource `json:"waitingOnResource,omitempty"`
}

type WaitingOnResource struct {
	CheckSuiteID types.GlobalID `json:"checkSuiteId,omitempty"`
	CheckRunID   types.GlobalID `json:"checkRunId,omitempty"`
	Identifier   string         `json:"identifier,omitempty"`
}

// CreateCheckRun runs mutationCreateCheckRun
func (c *client) CreateCheckRun(ctx context.Context, req CreateCheckRunRequest) (CheckRunResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var res CheckRunResponse

	data := struct {
		Node struct {
			CheckRun struct {
				GlobalID   types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
				CheckSuite struct {
					GlobalID   types.GlobalID `json:"id"`
					DatabaseID int64          `json:"databaseId"`
				} `json:"checkSuite"`
			} `json:"checkRun"`
		} `json:"createCheckRun"`
	}{}

	if req.Conclusion == "" {
		req.CompletedAt = nil
	}
	if req.CompletedAt == nil {
		req.Conclusion = ""
	}

	optHeaders := http.Header{}

	optHeaders = c.setPermitReplicasHeader(optHeaders)

	variables := map[string]any{"create": req}
	_, err := c.do(ctx, "CreateCheckRun", "mutation", mutationCreateCheckRun, variables, &data, optHeaders)
	if err != nil {
		return res, err
	}

	res.CheckSuiteIDPair = types.IDPair{
		GlobalID:   data.Node.CheckRun.CheckSuite.GlobalID,
		DatabaseID: data.Node.CheckRun.CheckSuite.DatabaseID,
	}
	res.CheckRunIDPair = types.IDPair{
		GlobalID:   data.Node.CheckRun.GlobalID,
		DatabaseID: data.Node.CheckRun.DatabaseID,
	}

	return res, nil
}

// UpdateCheckRunRequest represents the request when updating a check run
//
// Doesn't have detailsUrl, actions, clientMutationId which are in graphql
type UpdateCheckRunRequest struct {
	// The Node ID of the repository.
	RepositoryID types.GlobalID `json:"repositoryId,omitempty"`
	// The ID of the CheckRun to update
	CheckRunID types.GlobalID `json:"checkRunId,omitempty"`
	// A reference for the run on the integrator's system.
	ExternalID string `json:"externalId,omitempty"`
	// The name of the check.
	Name string `json:"name,omitempty"`
	// The visible name of the check.
	DisplayName string `json:"displayName,omitempty"`
	// The time that the check run started.
	StartedAt *time.Time `json:"startedAt,omitempty"`
	// The time that the check run finished.
	CompletedAt *time.Time `json:"completedAt,omitempty"`
	// The current status.
	Status string `json:"status,omitempty"`
	// The final conclusion of the check.
	Conclusion string `json:"conclusion,omitempty"`
	// Descriptive details about the run.
	Output *CheckRunOutput `json:"output,omitempty"`
	// Steps this check run will execute.
	Steps []CheckStepData `json:"steps,omitempty"`
	// The completed log information.
	CompletedLog *CompletedLog `json:"completedLog,omitempty"`
	// The streaming log
	StreamingLog *StreamingLog `json:"streamingLog,omitempty"`
	// Summary URL information
	JobSummary *JobSummary `json:"jobSummary,omitempty"`
	// The topological order of the check run within the check suite.
	// Cannot be set to omitempty or a zero won't marshal.
	Number int64 `json:"number"`
	// Environment Name
	EnvironmentName string `json:"environment,omitempty"`
	// Environment Url
	EnvironmentURL string `json:"environmentUrl,omitempty"`
	// Labels
	Labels []string `json:"labels,omitempty"`
	// The ID of the self-hosted runner group, if the workflow_job has been assigned to a runner
	RunnerGroupID int64 `json:"runnerGroupId,omitempty"`
	// The name of the self-hosted runner group, iff the workflow_job has been assigned to a runner
	RunnerGroupName string `json:"runnerGroupName,omitempty"`
	// The ID of the self-hosted runner, if the workflow_job has been assigned to a runner
	RunnerID int64 `json:"runnerId,omitempty"`
	// The name of the self-hosted runner, if the workflow_job has been assigned to a runner
	RunnerName string `json:"runnerName,omitempty"`
	// Concurrency group that is blocking the run
	Concurrency *Concurrency `json:"concurrency,omitempty"`
	// Indicates if a partial rerun cloned this run
	IsClonedFromPreviousRun bool `json:"isClonedFromPreviousRun"`
}

// UpdateCheckSuiteRequest represents the request when updating a check suite
type UpdateCheckSuiteRequest struct {
	// The Node ID of the repository.
	RepositoryID types.GlobalID `json:"repositoryId,omitempty"`
	// The ID of the CheckSuite to update
	CheckSuiteID types.GlobalID `json:"checkSuiteId,omitempty"`
	// The artifacts generated during the suite's jobs
	Artifacts []*CheckRunArtifact `json:"artifacts,omitempty"`
	// The URL pointing to the zip file containing the completed log
	CompletedLogURL string `json:"completedLogUrl,omitempty"`

	// Any annotations the check suite can include.
	Annotations []CheckSuiteAnnotation `json:"annotations,omitempty"`
	// The conclusion if when the conclusion of the run is known (either in
	// a start error, or we're told by the backend)
	Conclusion string `json:"conclusion,omitempty"`
	// Concurrency group that is blocking the suite
	Concurrency *Concurrency `json:"concurrency,omitempty"`
	// A reference for the run on the integrator's system
	ExternalID string `json:"externalId,omitempty"`
}

// UpdateCheckRun runs mutationUpdateCheckRun
func (c *client) UpdateCheckRun(ctx context.Context, req UpdateCheckRunRequest) (CheckRunResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var res CheckRunResponse

	data := struct {
		Node struct {
			CheckRun struct {
				GlobalID   types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
				CheckSuite struct {
					GlobalID   types.GlobalID `json:"id"`
					DatabaseID int64          `json:"databaseId"`
				} `json:"checkSuite"`
			} `json:"checkRun"`
		} `json:"updateCheckRun"`
	}{}

	if req.Conclusion == "" {
		req.CompletedAt = nil
	}
	if req.CompletedAt == nil {
		req.Conclusion = ""
	}

	variables := map[string]any{"update": req}
	_, err := c.do(ctx, "UpdateCheckRun", "mutation", mutationUpdateCheckRun, variables, &data, nil)
	if err != nil {
		return res, errors.Wrap(err, "failed to update CheckRun")
	}

	res.CheckSuiteIDPair = types.IDPair{
		GlobalID:   data.Node.CheckRun.CheckSuite.GlobalID,
		DatabaseID: data.Node.CheckRun.CheckSuite.DatabaseID,
	}
	res.CheckRunIDPair = types.IDPair{
		GlobalID:   data.Node.CheckRun.GlobalID,
		DatabaseID: data.Node.CheckRun.DatabaseID,
	}

	return res, nil
}

// UpdateCheckSuite runs mutationUpdateCheckSuite
func (c *client) UpdateCheckSuite(ctx context.Context, req UpdateCheckSuiteRequest) (*types.IDPair, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data := struct {
		Node struct {
			CheckSuite struct {
				GlobalID   types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
			} `json:"checkSuite"`
		} `json:"updateCheckSuite"`
	}{}

	variables := map[string]any{"input": req}
	_, err := c.do(ctx, "UpdateCheckSuite", "mutation", mutationUpdateCheckSuite, variables, &data, nil)
	if err != nil {
		return nil, err
	}

	return &types.IDPair{
		GlobalID:   data.Node.CheckSuite.GlobalID,
		DatabaseID: data.Node.CheckSuite.DatabaseID,
	}, nil
}

const mutationUpdateCheckSuite = `mutation UpdateCheckSuite($input: UpdateCheckSuiteInput!) {
	updateCheckSuite(input: $input) {
		checkSuite {
			id
			databaseId
		}
	}
}`

// CreateGateRequestRequest represents the request when updating a gate request
type CreateGateRequestRequest struct {
	// The Node ID of the gate.
	GateID types.GlobalID `json:"gateId,omitempty"`
	// The ID of the CheckRun to update
	CheckRunID types.GlobalID `json:"checkRunId,omitempty"`
	// The token that will be required to send to actions service to open the gate
	Token string `json:"token,omitempty"`
	// The state of the gate request
	State string `json:"state,omitempty"`
	// The conclusion status of the gate request
	Concluded bool `json:"concluded,omitempty"`
	// The datetime the gate expires at.
	ExpiresAt time.Time `json:"expiresAt,omitempty"`
}

// CreateGateRequest runs mutationCreateGateRequest
func (c *client) CreateGateRequest(ctx context.Context, req CreateGateRequestRequest) (*types.IDPair, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data := struct {
		Node struct {
			GateRequest struct {
				GlobalID   types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
			} `json:"gateRequest"`
		} `json:"createGateRequest"`
	}{}

	variables := map[string]any{"input": req}
	_, err := c.do(ctx, "CreateGateRequest", "mutation", mutationCreateGateRequest, variables, &data, nil)
	if err != nil {
		return nil, err
	}

	return &types.IDPair{
		GlobalID:   data.Node.GateRequest.GlobalID,
		DatabaseID: data.Node.GateRequest.DatabaseID,
	}, nil
}

const mutationCreateGateRequest = `mutation CreateGateRequest($input: CreateGateRequestInput!) {
	createGateRequest(input: $input) {
		gateRequest {
			id
			databaseId
		}
	}
}`

// EnvironmentResponse represents the response to creating, updating, or getting an Environment
type EnvironmentResponse struct {
	EnvironmentID types.GlobalID
	DatabaseID    int64
	Name          string
	Gates         []*Gate
}

// Gate information returned by CreateEnvironment
type Gate struct {
	GateID           types.GlobalID
	DatabaseID       int64
	GateType         string
	TimeoutInMinutes int32
}

const mutationCreateEnvironment = `mutation CreateEnvironment($create: CreateEnvironmentInput!) {
	createEnvironment(input: $create) {
		environment {
			id
			databaseId
			name
			gates(first: 100) {
				edges {
					node {
						id
						databaseId
						type
						timeout
					}
				}
			}
		}
	}
}`

type createEnvironmentRequest struct {
	// The Node ID of the repository.
	RepositoryID types.GlobalID `json:"repositoryId"`
	// The environment name
	Name string `json:"name,omitempty"`
}

// CreateEnvironment creates an environment with idempotency
func (c *client) CreateEnvironment(ctx context.Context, repo types.GlobalID, env string) (*EnvironmentResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	req := createEnvironmentRequest{
		RepositoryID: repo,
		Name:         env,
	}

	var data struct {
		CreateEnvironment struct {
			Environment struct {
				ID         types.GlobalID `json:"id"`
				DatabaseID int64          `json:"databaseId"`
				Name       string         `json:"name"`
				Gates      struct {
					Edges []struct {
						Node struct {
							ID         types.GlobalID `json:"id"`
							DatabaseID int64          `json:"databaseId"`
							GateType   string         `json:"type"`
							Timeout    int32          `json:"timeout"`
						} `json:"node"`
					} `json:"edges"`
				} `json:"gates"`
			}
		} `graphql:"createEnvironment"`
	}

	variables := map[string]any{"create": req}
	_, err := c.do(ctx, "CreateEnvironment", "mutation", mutationCreateEnvironment, variables, &data, nil)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	edges := data.CreateEnvironment.Environment.Gates.Edges
	gates := make([]*Gate, 0, len(edges))

	for _, edge := range edges {
		gates = append(gates, &Gate{
			GateID:           edge.Node.ID,
			DatabaseID:       edge.Node.DatabaseID,
			GateType:         edge.Node.GateType,
			TimeoutInMinutes: edge.Node.Timeout,
		})
	}

	res := &EnvironmentResponse{
		EnvironmentID: data.CreateEnvironment.Environment.ID,
		DatabaseID:    data.CreateEnvironment.Environment.DatabaseID,
		Name:          data.CreateEnvironment.Environment.Name,
		Gates:         gates,
	}

	return res, nil
}

const mutationReusePreviousWorkflowRun = `mutation ReusePreviousWorkflowRun($reuse: ReusePreviousWorkflowRunInput!) {
	reusePreviousWorkflowRun(input: $reuse) {
		checkSuite {
            id
            databaseId
            workflowRun {
                id
                databaseId
            }
        }
	}
}`

type ReusePreviousWorkflowRequest struct {
	// The Node ID of the repository (Required)
	RepositoryID types.GlobalID `json:"repositoryId,omitempty"`
	// The ID of the CheckSuite to clone (Required)
	CheckSuiteToClone types.GlobalID `json:"checkSuiteToClone,omitempty"`
	// The event that triggered the workflow run (Required)
	Event string `json:"event,omitempty"`
	// The Node ID of the creator. (Required)
	CreatorID types.GlobalID `json:"creatorId,omitempty"`
	// The entity that triggered the workflow run. (Required)
	TriggerID types.GlobalID `json:"triggerId,omitempty"`
	// The head_sha of the new check suite that will be created. (Not Required. Can be nil for push events)
	HeadSha types.CommitSha `json:"headSha,omitempty"`
	// The branch of the new check suite that will be created.
	HeadBranch string `json:"headBranch,omitempty"`
	// The tree_id of the existing workflow run that will be reused. (Required.)
	TreeID types.CommitSha `json:"treeId,omitempty"`
}

// ReusePreviousWorkflowRunResponse represents the response to workflow run reuse requet
type ReusePreviousWorkflowRunResponse struct {
	// A CheckSuite ID of the newly created check suite
	CheckSuiteID types.GlobalID
	// A CheckSuite DatabaseID of the newly created check suite
	CheckSuiteDatabaseID int64
	// A WorkflowRun ID of the newly created workflow run
	WorkflowRunID types.GlobalID
	// A WorkflowRun DatabaseID of the newly created workflow run
	WorkflowRunDatabaseID int64
}

// CreateGateRequest runs mutationCreateGateRequest
func (c *client) ReusePreviousWorkflowRun(ctx context.Context, req ReusePreviousWorkflowRequest) (*ReusePreviousWorkflowRunResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	data := struct {
		Node struct {
			CheckSuite struct {
				GlobalID    types.GlobalID `json:"id"`
				DatabaseID  int64          `json:"databaseId"`
				WorkflowRun struct {
					GlobalID   types.GlobalID `json:"id"`
					DatabaseID int64          `json:"databaseId"`
				} `json:"workflowRun"`
			} `json:"checkSuite"`
		} `json:"reusePreviousWorkflowRun"`
	}{}

	variables := map[string]any{"reuse": req}
	_, err := c.do(ctx, "ReusePreviousWorkflowRun", "mutation", mutationReusePreviousWorkflowRun, variables, &data, nil)
	if err != nil {
		return nil, errors.Wrap(err, "failed to reuse a previous workflow run")
	}

	return &ReusePreviousWorkflowRunResponse{
		CheckSuiteID:          data.Node.CheckSuite.GlobalID,
		CheckSuiteDatabaseID:  data.Node.CheckSuite.DatabaseID,
		WorkflowRunID:         data.Node.CheckSuite.WorkflowRun.GlobalID,
		WorkflowRunDatabaseID: data.Node.CheckSuite.WorkflowRun.DatabaseID,
	}, nil
}
