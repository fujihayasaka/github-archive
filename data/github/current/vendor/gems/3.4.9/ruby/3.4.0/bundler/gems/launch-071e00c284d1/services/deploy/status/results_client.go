package status

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/launch/observability/ctxstash"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	proto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/pkg/results/entities/actions"
	"github.com/github/launch/pkg/results/entities/checks"
	"github.com/github/launch/pkg/results/entities/events"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
)

// resultsStatusClient handles status updates that are sent to the results service
// currently behind a feature flag
type resultsStatusClient struct {
	aqueductClient aqueduct.Client
	resultsApp     string
	log            logs
}

var _ statusClient = (*resultsStatusClient)(nil)

const (
	actionsResultsEventsQueue = "actions-results-events"
	actionsResultsEventHeader = "actions-results-event"
	gateRequestUpdateEvent    = "gate-request-update"
	workflowRunUpdateEvent    = "workflow-run-update"
	workflowJobRunUpdateEvent = "workflow-job-run-update"
)

var (
	statusResultsMap = map[Status]checks.CheckStatus{
		Status_STATUS_ALL:         checks.CheckStatus_STATUS_UNKNOWN,
		Status_STATUS_CANCELLING:  checks.CheckStatus_STATUS_IN_PROGRESS,
		Status_STATUS_COMPLETED:   checks.CheckStatus_STATUS_COMPLETED,
		Status_STATUS_IN_PROGRESS: checks.CheckStatus_STATUS_IN_PROGRESS,
		Status_STATUS_NONE:        checks.CheckStatus_STATUS_QUEUED,
		Status_STATUS_NOT_STARTED: checks.CheckStatus_STATUS_QUEUED,
		Status_STATUS_POSTPONED:   checks.CheckStatus_STATUS_QUEUED,
		Status_STATUS_PENDING:     checks.CheckStatus_STATUS_PENDING,
	}

	resultResultsConclusionMap = map[Result]checks.CheckConclusion{
		Result_RESULT_CANCELED:            checks.CheckConclusion_CONCLUSION_CANCELLED,
		Result_RESULT_FAILED:              checks.CheckConclusion_CONCLUSION_FAILURE,
		Result_RESULT_NONE:                checks.CheckConclusion_CONCLUSION_UNKNOWN,
		Result_RESULT_PARTIALLY_SUCCEEDED: checks.CheckConclusion_CONCLUSION_SUCCESS,
		Result_RESULT_SUCCEEDED:           checks.CheckConclusion_CONCLUSION_SUCCESS,
		Result_RESULT_SKIPPED:             checks.CheckConclusion_CONCLUSION_SKIPPED,
	}

	annotationLevelResultsMap = map[AnnotationLevel]checks.CheckAnnotation_AnnotationLevel{
		AnnotationLevel_LEVEL_NOTICE:  checks.CheckAnnotation_LEVEL_NOTICE,
		AnnotationLevel_LEVEL_WARNING: checks.CheckAnnotation_LEVEL_WARNING,
		AnnotationLevel_LEVEL_FAILURE: checks.CheckAnnotation_LEVEL_FAILURE,
		AnnotationLevel_LEVEL_UNKNOWN: checks.CheckAnnotation_LEVEL_UNKNOWN,
	}

	runConclusionResultsConclusionMap = map[RunConclusion]checks.CheckConclusion{
		RunConclusion_SUCCEEDED:    checks.CheckConclusion_CONCLUSION_SUCCESS,
		RunConclusion_CANCELED:     checks.CheckConclusion_CONCLUSION_CANCELLED,
		RunConclusion_FAILED:       checks.CheckConclusion_CONCLUSION_FAILURE,
		RunConclusion_SKIPPED:      checks.CheckConclusion_CONCLUSION_SKIPPED,
		RunConclusion_NOT_PROVIDED: checks.CheckConclusion_CONCLUSION_UNKNOWN,
	}

	gateStateResultsMap = map[GateState]actions.GateRequestState{
		closed: actions.GateRequestState_STATE_CLOSED,
		open:   actions.GateRequestState_STATE_OPEN,
	}

	statusAqueductOptions = []aqueduct.SendOption{
		aqueduct.WithJobRedeliveryTimeoutSeconds(120), // default is 600 (10 minutes)
		aqueduct.WithJobMaxRedeliveryAttempts(4),      // default is 2 redeliveries (first delivery doesn't count)
	}
)

func newResultsStatusClient(aqueductClient aqueduct.Client, log logs) *resultsStatusClient {
	return &resultsStatusClient{
		aqueductClient: aqueductClient,
		resultsApp:     "actions-results-production",
		log:            log,
	}
}

func (client *resultsStatusClient) UpdateGateStatus(ctx context.Context, gsr *GateStatusRequest, params UpdateGateStatusParams) error {
	// Build the update gate status event that will be sent to the results service
	workflowUpdate, err := buildUpdateGateStatusResults(gsr, params)
	if err != nil {
		return errors.Wrap(err, "unable to build results gate status update")
	}

	payload, err := proto.Marshal(workflowUpdate)
	if err != nil {
		return errors.Wrap(err, "unable to marshal workflow update payload")
	}

	jobID, err := client.aqueductClient.Send(ctx, aqueduct.Job{
		App:     client.resultsApp,
		Queue:   actionsResultsEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    gateRequestUpdateEvent,
			results.RequestIDHeader:      ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, statusAqueductOptions...)

	client.log.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", client.resultsApp),
		kvp.String("gh.aqueduct.queue.name", actionsResultsEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobID))

	if err != nil {
		return err
	}
	return nil
}

func (client *resultsStatusClient) UpdateCheckSuite(ctx context.Context, req *RunStatusRequest, params UpdateCheckSuiteParams) error {
	// Build the update check suite event that will be sent to the results service
	workflowUpdate, err := buildUpdateCheckSuiteResults(req, params)
	if err != nil {
		return errors.Wrap(err, "unable to build results check suite update")
	}

	payload, err := proto.Marshal(workflowUpdate)
	if err != nil {
		return errors.Wrap(err, "unable to marshal workflow update payload")
	}

	jobID, err := client.aqueductClient.Send(ctx, aqueduct.Job{
		App:     client.resultsApp,
		Queue:   actionsResultsEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    workflowRunUpdateEvent,
			results.RequestIDHeader:      ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, statusAqueductOptions...)

	client.log.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", client.resultsApp),
		kvp.String("gh.aqueduct.queue.name", actionsResultsEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobID))

	if err != nil {
		return err
	}
	return nil
}

func (client *resultsStatusClient) UpdateCheckRun(ctx context.Context, req *JobStatusRequest, params UpdateCheckRunParams) error {
	// Build the update check run event that will be sent to the results service
	workflowJobUpdate, err := buildUpdateCheckRunResults(req, params)
	if err != nil {
		return errors.Wrap(err, "unable to build results check suite update")
	}

	payload, err := proto.Marshal(workflowJobUpdate)
	if err != nil {
		return errors.Wrap(err, "unable to marshal workflow job update payload")
	}

	jobID, err := client.aqueductClient.Send(ctx, aqueduct.Job{
		App:     client.resultsApp,
		Queue:   actionsResultsEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    workflowJobRunUpdateEvent,
			results.RequestIDHeader:      ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, statusAqueductOptions...)

	client.log.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", client.resultsApp),
		kvp.String("gh.aqueduct.queue.name", actionsResultsEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobID))

	if err != nil {
		return err
	}
	return nil
}

func buildUpdateGateStatusResults(update *GateStatusRequest, params UpdateGateStatusParams) (*events.GateRequestUpdate, error) {
	repositoryID, err := getRepositoryID(params.RepositoryID)
	if err != nil {
		return nil, err
	}

	workflowRunGUID := getWorkflowRunGUIDFromExternalID(update.ExternalId)

	gateID, err := getGateID(update.GateId)
	if err != nil {
		return nil, err
	}

	checkRunID, err := getCheckRunID(params.CheckRunID)
	if err != nil {
		return nil, err
	}

	state := getGateStatusResults(update.IsOpen)

	return &events.GateRequestUpdate{
		RepositoryId:    repositoryID,
		WorkflowRunGuid: workflowRunGUID,
		CheckRunId:      checkRunID,
		GateId:          gateID,
		Token:           update.Token,
		State:           state,
		Concluded:       update.IsConcluded,
		ExpiresAt:       update.Deadline,
	}, nil
}

func buildUpdateCheckSuiteResults(update *RunStatusRequest, params UpdateCheckSuiteParams) (*events.WorkflowRunUpdate, error) {
	repositoryID, err := getRepositoryID(params.CheckSuiteState.RepositoryID)
	if err != nil {
		return nil, err
	}

	checkSuiteID, err := getCheckSuiteID(params.CheckSuiteState.CheckSuiteIDPair.GlobalID)
	if err != nil {
		return nil, err
	}

	status := getCheckSuiteStatus(update)

	conclusion := getCheckSuiteConclusion(update)

	completedLogURL := getCompletedLogURL(update.CompletedLog)

	artifacts := getArtifacts(update.Artifacts)

	concurrency, err := getConcurrency(update.Concurrency, params.WaitingOn)
	if err != nil {
		return nil, err
	}

	workflowRunUpdate := &events.WorkflowRunUpdate{
		RepositoryId:    repositoryID,
		WorkflowRunGuid: update.WorkflowId,
		CheckSuiteId:    checkSuiteID,
		Status:          status,
		Conclusion:      conclusion,
		CompletedLogUrl: completedLogURL,
		Artifacts:       artifacts,
		Concurrency:     concurrency,
	}

	isCompleted := update.GetComplete() != nil
	if isCompleted {
		workflowRunUpdate.StartedAt = update.GetComplete().GetStartedAt()
		workflowRunUpdate.CompletedAt = update.GetComplete().GetCompletedAt()
		workflowRunUpdate.ExpiresAt = update.GetComplete().GetExpiresAt()
		workflowRunUpdate.IsInfraFailure = update.GetComplete().GetIsInfraFailure()

		if len(update.Annotations) > 0 {
			workflowRunUpdate.Annotations = getCheckAnnotations(update.Annotations)
		}
	}

	return workflowRunUpdate, nil
}

func buildUpdateCheckRunResults(update *JobStatusRequest, params UpdateCheckRunParams) (*events.WorkflowJobRunUpdate, error) {
	repositoryID, err := getRepositoryID(params.CheckSuiteState.RepositoryID)
	if err != nil {
		return nil, err
	}

	workflowRunGUID := update.WorkflowId

	checkRunID, err := getCheckRunID(params.CheckRunID)
	if err != nil {
		return nil, err
	}

	status := getCheckRunStatus(update)

	conclusion := getCheckRunConclusion(update)

	annotations := getCheckAnnotations(update.Annotations)

	artifacts := getArtifacts(update.Artifacts)

	steps, err := getStepsResults(update.Steps)
	if err != nil {
		return nil, err
	}

	environment := getEnvironmentResults(update.Environment)

	concurrency, err := getConcurrency(update.Concurrency, params.WaitingOn)
	if err != nil {
		return nil, err
	}

	workflowJobRunUpdate := &events.WorkflowJobRunUpdate{
		RepositoryId:            repositoryID,
		WorkflowRunGuid:         workflowRunGUID,
		CheckRunId:              checkRunID,
		Status:                  status,
		Conclusion:              conclusion,
		Name:                    update.JobId,
		ExternalId:              update.ExternalId,
		Number:                  update.Number,
		DisplayName:             update.DisplayName,
		Annotations:             annotations,
		Artifacts:               artifacts,
		Steps:                   steps,
		Environment:             environment,
		JobKey:                  update.JobKey,
		ParentJobId:             update.ParentJobId,
		Concurrency:             concurrency,
		Labels:                  update.Labels,
		RunnerId:                update.RunnerId,
		RunnerName:              update.RunnerName,
		RunnerGroupId:           update.RunnerGroupId,
		RunnerGroupName:         update.RunnerGroupName,
		IsClonedFromPreviousRun: update.IsClonedFromPreviousRun,
	}

	switch st := update.Progress.(type) {
	case *JobStatusRequest_InProgress:
		workflowJobRunUpdate.StartedAt = st.InProgress.GetStartedAt()

		if st.InProgress.LogStream != nil {
			workflowJobRunUpdate.StreamingLogUrl = wrapperspb.String(st.InProgress.LogStream.GetUrl())
		}

		if st.InProgress.Log != nil {
			workflowJobRunUpdate.CompletedLogUrl = wrapperspb.String(st.InProgress.Log.GetUrl())
			workflowJobRunUpdate.CompletedLogLines = wrapperspb.Int64(st.InProgress.Log.GetLines())
		}

	case *JobStatusRequest_Complete:
		if st.Complete.StartedAt != nil {
			workflowJobRunUpdate.StartedAt = st.Complete.GetStartedAt()
		}

		if st.Complete.CompletedAt != nil {
			workflowJobRunUpdate.CompletedAt = st.Complete.GetCompletedAt()
		}

		if st.Complete.Log != nil {
			workflowJobRunUpdate.CompletedLogUrl = wrapperspb.String(st.Complete.Log.GetUrl())
			workflowJobRunUpdate.CompletedLogLines = wrapperspb.Int64(st.Complete.Log.GetLines())
		}

		if st.Complete.SummaryUrl != "" {
			workflowJobRunUpdate.SummaryUrl = wrapperspb.String(st.Complete.SummaryUrl)
		}

	default:
		return nil, errors.Errorf("invalid job progress type type %q", st)
	}

	return workflowJobRunUpdate, nil
}

// Gets the workflow run GUID from the external ID by splitting on the first comma
func getWorkflowRunGUIDFromExternalID(externalID string) string {
	idParts := strings.Split(externalID, ",")
	return idParts[0]
}

// Gets the repository ID from the global ID, checking that it is a repository global ID
func getRepositoryID(globalID types.GlobalID) (int64, error) {
	t, id, err := graphqlid.Decode(globalID.String())
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode Repository GlobalID")
	}

	if t != "Repository" {
		return 0, errors.Errorf("Unexpected global id type %s, expected Repository", t)
	}

	return strconv.ParseInt(id, 10, 64)
}

// Gets the gate ID from the global ID, checking that it is a gate global ID
func getGateID(globalID string) (int64, error) {
	t, id, err := graphqlid.Decode(globalID)
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode Gate GlobalID")
	}

	if t != "Gate" {
		msg := fmt.Sprintf("Unexpected global id type %s, expected Gate", t)
		return 0, kvperrors.With(msg, kvp.String("code.function", "getGateID"))
	}

	return strconv.ParseInt(id, 10, 64)
}

// Gets the check suite ID from the global ID, checking that it is a check suite global ID
func getCheckSuiteID(globalID types.GlobalID) (int64, error) {
	t, id, err := graphqlid.Decode(globalID.String())
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode Check Suite GlobalID")
	}

	if t != "CheckSuite" {
		msg := fmt.Sprintf("Unexpected global id type %s, expected CheckSuite", t)
		return 0, kvperrors.With(msg, kvp.String("code.function", "getCheckSuiteID"))
	}

	return strconv.ParseInt(id, 10, 64)
}

// Gets the check run ID from the global ID, checking that it is a check run global ID
func getCheckRunID(globalID types.GlobalID) (int64, error) {
	t, id, err := graphqlid.Decode(globalID.String())
	if err != nil {
		return 0, errors.Wrap(err, "failed to decode Check Run GlobalID")
	}

	if t != "CheckRun" {
		msg := fmt.Sprintf("Unexpected global id type %s, expected CheckRun", t)
		return 0, kvperrors.With(msg, kvp.String("code.function", "getCheckRunID"))
	}

	return strconv.ParseInt(id, 10, 64)
}

// Gets the gate status using the gateStaeResultsMap
func getGateStatusResults(isOpen bool) actions.GateRequestState {
	state := closed
	if isOpen {
		state = open
	}

	gateState, ok := gateStateResultsMap[state]
	if !ok { // impossible to get here, but adding for any future states
		return actions.GateRequestState_STATE_UNKNOWN
	}

	return gateState
}

// Gets the status of the check suite from the RunStatusRequest Progress type
func getCheckSuiteStatus(update *RunStatusRequest) checks.CheckStatus {
	status := checks.CheckStatus_STATUS_UNKNOWN
	switch update.Progress.(type) {
	case *RunStatusRequest_Complete:
		status = checks.CheckStatus_STATUS_COMPLETED
	case *RunStatusRequest_NotStarted:
		status = checks.CheckStatus_STATUS_PENDING
	}

	return status
}

// Gets the status of the check run from the JobStatusRequest Progress type
func getCheckRunStatus(update *JobStatusRequest) checks.CheckStatus {
	status := checks.CheckStatus_STATUS_UNKNOWN
	switch progress := update.Progress.(type) {
	case *JobStatusRequest_Complete:
		status = checks.CheckStatus_STATUS_COMPLETED
	case *JobStatusRequest_InProgress:
		if val, ok := statusResultsMap[progress.InProgress.GetStatus()]; ok {
			status = val
		}
	}

	return status
}

// Gets the conclusion of the check suite from the RunStatusRequest Complete Conclusion using the runConclusionResultsConclusionMap
func getCheckSuiteConclusion(update *RunStatusRequest) checks.CheckConclusion {
	completed := update.GetComplete()
	conclusion := completed.GetConclusion()

	checkSuiteConclusion, ok := runConclusionResultsConclusionMap[conclusion]

	if !ok {
		checkSuiteConclusion = checks.CheckConclusion_CONCLUSION_UNKNOWN
	}

	return checkSuiteConclusion
}

// Gets the conclusion of the check run from the JobStatusRequest Complete Conclusion using the resultResultsConclusionMap
func getCheckRunConclusion(update *JobStatusRequest) checks.CheckConclusion {
	completed := update.GetComplete()
	result := completed.GetResult()

	runConclusion, ok := resultResultsConclusionMap[result]
	if !ok {
		runConclusion = checks.CheckConclusion_CONCLUSION_UNKNOWN
	}

	return runConclusion
}

// Gets check annotations array from status annotations
func getCheckAnnotations(annotations []*Annotation) []*checks.CheckAnnotation {
	out := make([]*checks.CheckAnnotation, 0, len(annotations))

	for _, annotation := range annotations {
		annotationLevel, ok := annotationLevelResultsMap[annotation.AnnotationLevel]
		if !ok {
			annotationLevel = checks.CheckAnnotation_LEVEL_UNKNOWN
		}

		checkAnnotation := &checks.CheckAnnotation{
			AnnotationLevel: annotationLevel,
			Message:         annotation.Message,
			RawDetails:      wrapperspb.String(annotation.RawDetails),
			Path:            wrapperspb.String(annotation.Path),
			StartLine:       wrapperspb.Int64(annotation.StartLine),
			EndLine:         wrapperspb.Int64(annotation.EndLine),
			StartColumn:     wrapperspb.Int64(annotation.StartColumn),
			EndColumn:       wrapperspb.Int64(annotation.EndColumn),
			Title:           wrapperspb.String(annotation.Title),
			StepNumber:      wrapperspb.Int64(annotation.StepNumber),
		}
		out = append(out, checkAnnotation)
	}

	return out
}

// Gets completed log URL
func getCompletedLogURL(completedLog *Log) *wrapperspb.StringValue {
	return wrapperspb.String(completedLog.GetUrl())
}

// Gets artifacts from status artifacts
func getArtifacts(artifacts []*Artifact) []*actions.Artifact {
	out := make([]*actions.Artifact, 0, len(artifacts))

	for _, artifact := range artifacts {
		artifact := getArtifact(artifact)
		out = append(out, artifact)
	}
	return out
}

// Gets individual artifact from status artifact
func getArtifact(artifact *Artifact) *actions.Artifact {
	var expiresAt *timestamppb.Timestamp
	if artifact.ExpiresAt.IsValid() {
		expiresAt = artifact.ExpiresAt
	}

	return &actions.Artifact{
		Name:      artifact.Name,
		Size:      artifact.Size,
		SourceUrl: artifact.Url,
		CreatedAt: artifact.CreatedAt,
		ExpiresAt: expiresAt,
	}
}

// Gets concurrency and which resource is being waited for
func getConcurrency(concurrency *Concurrency, waitingOn *WaitingOn) (*actions.Concurrency, error) {
	var out *actions.Concurrency

	if concurrency != nil {
		out = &actions.Concurrency{
			Group: concurrency.Group,
		}

		if waitingOn != nil && !waitingOn.CheckSuiteID.IsZeroValue() {
			checkSuiteID, err := getCheckSuiteID(waitingOn.CheckSuiteID)
			if err != nil {
				return nil, errors.Wrap(err, "failed to get check suite ID")
			}
			out.WaitingOn = &actions.Concurrency_CheckSuiteId{CheckSuiteId: checkSuiteID}
		}

		if waitingOn != nil && !waitingOn.CheckRunID.IsZeroValue() {
			checkRunID, err := getCheckRunID(waitingOn.CheckRunID)
			if err != nil {
				return nil, errors.Wrap(err, "failed to get check run ID")
			}
			out.WaitingOn = &actions.Concurrency_CheckRunId{CheckRunId: checkRunID}
		}
	}

	return out, nil
}

// Gets all job steps in the results format
func getStepsResults(jobSteps []*JobStep) ([]*actions.Step, error) {
	out := make([]*actions.Step, 0, len(jobSteps))

	for _, step := range jobSteps {
		step, err := getStepResults(step)
		if err != nil {
			return nil, err
		}
		out = append(out, step)
	}
	return out, nil
}

// Gets an individual job steps in the results format
func getStepResults(step *JobStep) (*actions.Step, error) {
	out := actions.Step{
		ExternalId: step.ExternalId,
		Name:       step.Name,
		Number:     step.Number,
	}

	switch st := step.Progress.(type) {
	case *JobStep_Queued:
		out.Status = checks.CheckStatus_STATUS_QUEUED
		out.Conclusion = checks.CheckConclusion_CONCLUSION_UNKNOWN
	case *JobStep_InProgress:
		if st.InProgress.StartedAt != nil {
			out.StartedAt = st.InProgress.GetStartedAt()
		}
		status, ok := statusResultsMap[st.InProgress.Status]
		if !ok {
			return nil, errors.Errorf("invalid InProgress.Status type %q", st.InProgress.Status)
		}
		out.Status = status
		out.Conclusion = checks.CheckConclusion_CONCLUSION_UNKNOWN
	case *JobStep_Complete:
		if st.Complete.StartedAt != nil {
			out.StartedAt = st.Complete.GetStartedAt()
		}

		if st.Complete.CompletedAt != nil {
			out.CompletedAt = st.Complete.GetCompletedAt()
		}

		conclusion, ok := resultResultsConclusionMap[st.Complete.Result]
		if !ok {
			return nil, errors.Errorf("invalid Complete.Result type %q", st.Complete.Result)
		}
		out.Conclusion = conclusion
		out.Status = checks.CheckStatus_STATUS_COMPLETED

		if st.Complete.Log != nil {
			out.CompletedLogUrl = wrapperspb.String(st.Complete.Log.GetUrl())
			out.CompletedLogLines = wrapperspb.Int64(st.Complete.Log.GetLines())
		}
	default:
		return nil, errors.Errorf("invalid step progress type type %q", st)
	}

	return &out, nil
}

// Gets environment details in the results format
func getEnvironmentResults(environment *Environment) *actions.Environment {
	var out *actions.Environment

	if environment != nil {
		out = &actions.Environment{
			Name: environment.Name,
			Url:  environment.Url,
		}
	}

	return out
}
