package status

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/timestamp"
	tspb "github.com/golang/protobuf/ptypes/timestamp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/statter"
	st "github.com/github/launch/services/deploy/status"
)

// DefaultAnnotationPath is the fallback value for an invalid annotation path
var DefaultAnnotationPath = ".github"

var statusMap = map[string]st.Status{
	"all":        st.Status_STATUS_ALL,
	"cancelling": st.Status_STATUS_CANCELLING,
	"completed":  st.Status_STATUS_COMPLETED,
	"inProgress": st.Status_STATUS_IN_PROGRESS,
	"none":       st.Status_STATUS_NONE,
	"notStarted": st.Status_STATUS_NOT_STARTED,
	"postponed":  st.Status_STATUS_POSTPONED,
	"pending":    st.Status_STATUS_PENDING,
}

var resultMap = map[string]st.Result{
	"canceled":           st.Result_RESULT_CANCELED,
	"failed":             st.Result_RESULT_FAILED,
	"none":               st.Result_RESULT_NONE,
	"partiallySucceeded": st.Result_RESULT_PARTIALLY_SUCCEEDED,
	"succeeded":          st.Result_RESULT_SUCCEEDED,
	"skipped":            st.Result_RESULT_SKIPPED,
}

var runStatusMap = map[string]st.RunStatus{
	"pending":   st.RunStatus_PENDING,
	"completed": st.RunStatus_COMPLETED,
}

// see ADR https://github.com/github/c2c-actions/pull/321
var runConclusionMap = map[string]st.RunConclusion{
	"succeeded": st.RunConclusion_SUCCEEDED,
	"failed":    st.RunConclusion_FAILED,
	"canceled":  st.RunConclusion_CANCELED,
	"skipped":   st.RunConclusion_SKIPPED,
	// see https://github.com/github/c2c-actions/pull/321#discussion_r339768625
	"none":               st.RunConclusion_SUCCEEDED,
	"partiallySucceeded": st.RunConclusion_SUCCEEDED,
}

var annotationLevelMap = map[string]st.AnnotationLevel{
	"notice":  st.AnnotationLevel_LEVEL_NOTICE,
	"warning": st.AnnotationLevel_LEVEL_WARNING,
	"failure": st.AnnotationLevel_LEVEL_FAILURE,
}

func (s *Servicer) getJobStatusUpdateFromJSONPayload(ctx context.Context, wfid WorkflowID, jid JobID, raw []byte) (*st.JobStatusRequest, error) {
	var jsu JobStatusUpdateRequest
	if err := json.Unmarshal(raw, &jsu); err != nil {
		return nil, err
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.job.status", jsu.Status))

	artifacts := getArtifacts(jsu.Artifacts)

	steps, err := getSteps(jsu.Steps)
	if err != nil {
		return nil, err
	}

	environment := getEnvironment(jsu.Environment)
	if environment != nil {
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.job.environment", environment.Name))
	}

	status, ok := statusMap[jsu.Status]
	if !ok {
		return nil, fmt.Errorf("Invalid InProgress Status type %s", jsu.Status)
	}

	if jsu.Concurrency != nil && status != st.Status_STATUS_PENDING {
		return nil, fmt.Errorf("Concurrency is not supported with status '%s'", jsu.Status)
	}

	ctx = ctxstash.WithFields(ctx, kvp.Int("gh.launch.job.labels_count", len(jsu.Runtime.Labels)))

	psu := st.JobStatusRequest{
		WorkflowId:              string(wfid),
		JobId:                   string(jid),
		DisplayName:             jsu.Name,
		ExternalId:              jsu.ExternalID,
		Number:                  jsu.Number,
		Artifacts:               artifacts,
		Steps:                   steps,
		JobKey:                  jsu.JobKey,
		Runtime:                 jsu.Runtime.Name,
		RuntimeVersion:          jsu.Runtime.Version,
		SelfHosted:              jsu.Runtime.SelfHosted,
		Labels:                  jsu.Runtime.Labels,
		RunnerId:                jsu.Runtime.RunnerID,
		RunnerName:              jsu.Runtime.RunnerName,
		RunnerGroupId:           jsu.Runtime.RunnerGroupID,
		RunnerGroupName:         jsu.Runtime.RunnerGroupName,
		DurationMs:              jsu.DurationMs,
		Delayed:                 jsu.Delayed,
		ParentJobId:             jsu.ParentJobID,
		Environment:             environment,
		IsClonedFromPreviousRun: jsu.IsClonedFromPreviousRun,
		BillableOwnerId:         jsu.BillableOwnerID,
		CustomerId:              jsu.CustomerID,
		ProductSku:              jsu.ProductSku,
	}

	queuedAt := timestamppb.New(jsu.QueuedAt)
	if jsu.QueuedAt.IsZero() {
		queuedAt = nil
	}

	psu.QueuedAt = queuedAt

	startedAt := timestamppb.New(jsu.StartedAt)
	if err != nil {
		return nil, err
	}
	if jsu.StartedAt.IsZero() {
		startedAt = nil
	}

	if jsu.IsCompleted() {
		if jsu.Conclusion == nil {
			return nil, kvperrors.With("Job is completed but no conclusion was provided",
				kvp.String("gh.actions.plan_id", string(wfid)),
				kvp.String("gh.launch.job.id", string(jid)),
			)
		}

		result, ok := resultMap[*jsu.Conclusion]
		if !ok {
			return nil, fmt.Errorf("Invalid Completed Result type %s", *jsu.Conclusion)
		}
		completedAt := timestamppb.New(jsu.CompletedAt)
		if err != nil {
			return nil, err
		}

		psu.Progress = &st.JobStatusRequest_Complete{
			Complete: &st.JobComplete{
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				Result:      result,
			},
		}

		if jsu.Runtime.RunnerType != nil {
			psu.RunnerType = *jsu.Runtime.RunnerType
		}

		if jsu.Runtime.RunnerProperties != nil {
			// Store the Raw properties JSON as a string
			raw, err := jsu.Runtime.RunnerProperties.MarshalJSON()
			if err != nil {
				return nil, err
			}

			buf := &bytes.Buffer{}

			// Compact the JSON to decrease the size
			if err = json.Compact(buf, raw); err != nil {
				return nil, err
			}

			psu.RunnerProperties = buf.String()
		}

		if jsu.SummaryURL != nil {
			completed := psu.GetComplete()
			completed.SummaryUrl = *jsu.SummaryURL
		}

		if jsu.CompletedLog != nil {
			logCompletedAt := timestamppb.New(jsu.CompletedLog.CreatedAt)
			if err != nil {
				return nil, err
			}

			completed := psu.GetComplete()
			completed.Log = &st.Log{
				Url:       jsu.CompletedLog.URL,
				Lines:     jsu.CompletedLog.Lines,
				CreatedAt: logCompletedAt,
			}
		}

		annotations, err := getAnnotations(jsu.Annotations)
		if err != nil {
			// we don't want to prevent the update if annotations fail
			// so we'll report it for further investigation if it does
			annotations = []*st.Annotation{}
			s.Log.Report(ctx, err,
				kvp.String("gh.actions.plan_id", string(wfid)),
				kvp.String("gh.launch.job.id", string(jid)),
			)
			s.Stats.Counter(ctx, "annotations.failure", statter.Tags{
				"type": "job",
			}, 1)
		}
		psu.Annotations = annotations

		return &psu, nil
	}

	// It is still in progress:

	if status == st.Status_STATUS_PENDING {
		if jsu.Concurrency != nil {
			psu.Concurrency = getConcurrency(jsu.Concurrency)
		} else {
			return nil, fmt.Errorf("Workflow is set to 'Pending' but no concurrency information was provided: %s", string(wfid))
		}
	}

	var logStream *st.LogStream

	if jsu.LogStream != nil {
		tokenExpiresAt := timestamppb.New(jsu.LogStream.TokenExpiresAt)
		if err != nil {
			return nil, err
		}
		logStream = &st.LogStream{
			Url:       jsu.LogStream.URL,
			Token:     jsu.LogStream.Token,
			ExpiresAt: tokenExpiresAt,
		}
	}

	var log *st.Log

	if jsu.CompletedLog != nil {
		logCompletedAt := timestamppb.New(jsu.CompletedLog.CreatedAt)
		if err != nil {
			return nil, err
		}

		log = &st.Log{
			Url:       jsu.CompletedLog.URL,
			Lines:     jsu.CompletedLog.Lines,
			CreatedAt: logCompletedAt,
		}
	}

	psu.Progress = &st.JobStatusRequest_InProgress{
		InProgress: &st.JobInProgress{
			StartedAt: startedAt,
			Status:    status,
			LogStream: logStream,
			Log:       log,
		},
	}
	return &psu, nil
}

func (s *Servicer) getRunStatusUpdateFromJSONPayload(ctx context.Context, wfid WorkflowID, raw []byte) (*st.RunStatusRequest, error) {
	type runLog struct {
		URL string `json:"url"`
	}

	type runPostback struct {
		CompletedLog *runLog      `json:"completed_log"`
		Artifacts    []Artifact   `json:"artifacts"`
		Status       string       `json:"status"`
		Conclusion   string       `json:"conclusion"`
		CompletedAt  *time.Time   `json:"completed_at"`
		StartedAt    *time.Time   `json:"started_at"`
		ExpiresAt    *time.Time   `json:"expires_at"`
		Annotations  []Annotation `json:"annotations"`
		Concurrency  *Concurrency `json:"concurrency"`
	}

	var rpb runPostback

	if err := json.Unmarshal(raw, &rpb); err != nil {
		return nil, err
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.check_run.status", rpb.Status))
	rsu := &st.RunStatusRequest{
		WorkflowId: string(wfid),
	}

	status, ok := runStatusMap[rpb.Status]
	if !ok {
		return nil, fmt.Errorf("Invalid run status: %q", rpb.Status)
	}

	var conclusion *st.RunConclusion
	if rpb.Conclusion != "" {
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.run.conclusion", rpb.Conclusion))
		c, ok := runConclusionMap[rpb.Conclusion]
		if !ok {
			return nil, fmt.Errorf("Invalid run conclusion value %s", rpb.Conclusion)
		}
		conclusion = &c
	}

	var startedAt *timestamp.Timestamp
	var err error
	if rpb.StartedAt != nil {
		startedAt = timestamppb.New(*rpb.StartedAt)

	}

	var completedAt *timestamp.Timestamp
	if rpb.CompletedAt != nil {
		completedAt = timestamppb.New(*rpb.CompletedAt)
	}

	var expiresAt *timestamp.Timestamp
	if rpb.ExpiresAt != nil {
		expiresAt = timestamppb.New(*rpb.ExpiresAt)
	}

	if rpb.Concurrency != nil && status != st.RunStatus_PENDING {
		return nil, fmt.Errorf("Concurrency is not supported with status '%s'", rpb.Status)
	}

	if status == st.RunStatus_COMPLETED {
		rc := &st.RunComplete{
			Status:      status,
			StartedAt:   startedAt,
			CompletedAt: completedAt,
			ExpiresAt:   expiresAt,
		}
		if conclusion != nil {
			rc.Conclusion = *conclusion
		}
		rsu.Progress = &st.RunStatusRequest_Complete{
			Complete: rc,
		}
	} else if status == st.RunStatus_PENDING {
		rsu.Concurrency = getConcurrency(rpb.Concurrency)
		rsu.Progress = &st.RunStatusRequest_NotStarted{
			NotStarted: &st.RunNotStarted{
				Status: status,
			},
		}
	}

	if rpb.CompletedLog != nil {
		rsu.CompletedLog = &st.Log{
			Url: rpb.CompletedLog.URL,
		}
	}

	artifacts := getArtifacts(rpb.Artifacts)
	rsu.Artifacts = artifacts

	annotations, err := getAnnotations(rpb.Annotations)
	if err != nil {
		// we don't want to prevent the update if annotations fail
		// so we'll report it for further investigation if it does
		annotations = []*st.Annotation{}
		s.Log.Report(ctx, err,
			kvp.String("gh.actions.plan_id", string(wfid)),
		)
		s.Stats.Counter(ctx, "annotations.failure", statter.Tags{
			"type": "run",
		}, 1)
	}
	rsu.Annotations = annotations

	return rsu, nil
}

func (s *Servicer) getGateStatusUpdateFromJSONPayload(ctx context.Context, wfid WorkflowID, gateID GateID, payload []byte) (*st.GateStatusRequest, error) {
	type gatePostback struct {
		JobKey      string     `json:"job_key"`
		GateType    string     `json:"type"`
		ExternalID  string     `json:"external_id"`
		Token       string     `json:"token"`
		IsOpen      bool       `json:"is_open"`
		IsConcluded bool       `json:"is_concluded"`
		Deadline    *time.Time `json:"deadline"`
	}

	var gpb gatePostback

	if err := json.Unmarshal(payload, &gpb); err != nil {
		return nil, err
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.gate.id", string(gateID)))
	s.Log.Debug(ctx, "gate status update", kvp.Bool("gh.launch.gate.is_open", gpb.IsOpen), kvp.Bool("gh.launch.gate.is_concluded", gpb.IsConcluded))

	var deadline *timestamp.Timestamp
	if gpb.Deadline != nil {
		deadline = timestamppb.New(*gpb.Deadline)
	}

	gsu := &st.GateStatusRequest{
		GateId:      string(gateID),
		ExternalId:  string(wfid) + "," + gpb.ExternalID,
		Type:        gpb.GateType,
		Token:       gpb.Token,
		IsOpen:      gpb.IsOpen,
		IsConcluded: gpb.IsConcluded,
		Deadline:    deadline,
	}

	return gsu, nil
}

func getEnvironment(in *Environment) *st.Environment {
	var out *st.Environment
	if in != nil {
		out = &st.Environment{
			Name: in.Name,
			Url:  in.URL,
		}
	}

	return out
}

func getConcurrency(in *Concurrency) *st.Concurrency {
	var out *st.Concurrency
	if in != nil {
		waitingOnResource := getWaitingOnResource(in.WaitingOnResource)
		out = &st.Concurrency{
			Group:             in.Group,
			WaitingOnResource: waitingOnResource,
		}
	}

	return out
}

func getWaitingOnResource(in *WaitingOnResource) *st.WaitingOnResource {
	var out *st.WaitingOnResource
	if in != nil {
		out = &st.WaitingOnResource{
			RunExternalId: in.RunExternalID,
			JobExternalId: in.JobExternalID,
			Identifier:    in.Identifier,
		}
	}

	return out
}

func getArtifacts(in []Artifact) []*st.Artifact {
	var out []*st.Artifact
	for _, a := range in {
		createdAt := timestamppb.New(a.CreatedAt)

		var expiresAt *tspb.Timestamp
		if !a.ExpiresAt.IsZero() {
			expiresAt = timestamppb.New(a.ExpiresAt)
		}
		out = append(out, &st.Artifact{
			Name:      a.Name,
			Size:      a.Size,
			Url:       a.URL,
			CreatedAt: createdAt,
			ExpiresAt: expiresAt,
		})
	}
	return out
}

func getSteps(in []Step) ([]*st.JobStep, error) {
	var out []*st.JobStep
	for _, inStep := range in {
		step, err := getStep(inStep)
		if err != nil {
			return nil, err
		}
		out = append(out, step)
	}
	return out, nil
}

func getStep(in Step) (*st.JobStep, error) {
	out := st.JobStep{
		ExternalId: in.ExternalID,
		Number:     in.Number,
		Name:       in.Name,
	}

	if in.IsCompleted() {
		if in.Conclusion == nil {
			return nil, kvperrors.With("Step is completed but no conclusion was provided",
				kvp.String("gh.launch.step.external_id", in.ExternalID))
		}

		result, ok := resultMap[*in.Conclusion]
		if !ok {
			return nil, fmt.Errorf("Invalid Completed Step Result type %s", in.Status)
		}

		startedAt := timestamppb.New(in.StartedAt)
		completedAt := timestamppb.New(in.CompletedAt)

		out.Progress = &st.JobStep_Complete{
			Complete: &st.StepComplete{
				Result:      result,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
			},
		}

		if in.CompletedLog != nil {
			logCompletedAt := timestamppb.New(in.CompletedLog.CreatedAt)
			completed := out.GetComplete()
			completed.Log = &st.Log{
				Url:       in.CompletedLog.URL,
				Lines:     in.CompletedLog.Lines,
				CreatedAt: logCompletedAt,
			}
		}
	} else if in.IsStarted() {
		status, ok := statusMap[in.Status]
		if !ok {
			return nil, fmt.Errorf("Invalid Completed Step Result type %s", in.Status)
		}
		startedAt := timestamppb.New(in.StartedAt)
		out.Progress = &st.JobStep_InProgress{
			InProgress: &st.StepInProgress{
				Status:    status,
				StartedAt: startedAt,
			},
		}
	} else {
		out.Progress = &st.JobStep_Queued{
			Queued: &st.StepQueued{},
		}
	}
	return &out, nil
}

func getAnnotations(in []Annotation) ([]*st.Annotation, error) {
	var annotations []*st.Annotation
	for _, a := range in {
		level, ok := annotationLevelMap[a.AnnotationLevel]
		if !ok {
			return nil, fmt.Errorf("Invalid Annotation Level type %s", a.AnnotationLevel)
		}
		annotation := &st.Annotation{
			AnnotationLevel: level,
			Message:         a.Message,
			RawDetails:      a.RawDetails,
			Path:            a.Path,
			StartLine:       a.StartLine,
			EndLine:         a.EndLine,
			StartColumn:     a.StartColumn,
			EndColumn:       a.EndColumn,
			Title:           a.Title,
			StepNumber:      a.StepNumber,
		}

		if isEmptyAnnotationPath(annotation.Path) {
			annotation.Path = DefaultAnnotationPath
		}

		// file views start at line 1, so make sure these are at least 1-indexed
		if isEmptyAnnotationLines(annotation.StartLine, annotation.EndLine) {
			annotation.StartLine = 1
			annotation.EndLine = 1
		}

		isSameLine := annotation.StartLine == annotation.EndLine
		if !isSameLine {
			// if the annotation lines are different, columns cannot be specified
			annotation.StartColumn = 0
			annotation.EndColumn = 0
		} else if isInvalidAnnotationColumns(annotation.StartColumn, annotation.EndColumn) {
			// if the end column < start, set them to the same
			annotation.EndColumn = annotation.StartColumn
		}

		annotations = append(annotations, annotation)
	}
	return annotations, nil
}

// isEmptyAnnotationPath checks if the annotation path is empty
// Everything barring annotation_level and message is optional in our ADR
// but the Checks API has different requirements, here we apply some fairly
// sensible defaults if the values are considered empty.
//
// https://github.com/github/c2c-actions/blob/master/docs/adrs/1112-annotation-postbacks.md#annotation-contract
func isEmptyAnnotationPath(path string) bool {
	return strings.TrimSpace(path) == ""
}

// isEmptyAnnotationLines if the start or end lines of an annotation are zero value
// https://docs.github.com/en/graphql/reference/input-objects#checkannotationrange
func isEmptyAnnotationLines(startLine, endLine int64) bool {
	return startLine == 0 || endLine == 0
}

// isInvalidAnnotationColumns checks for correct order of start and end columns of an annotation
// https://github.com/github/github/blob/ea4a0f29c98e2475bc6c572c03fdb13281902212/app/models/check_annotation.rb#L55-L87
func isInvalidAnnotationColumns(startColumn, endColumn int64) bool {
	return startColumn > endColumn
}
