package agentcallback

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/telemetry"
	"github.com/github/sweagentd/internal/telemetry/standardevents"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const metricRuntimeTimingDurationMs = "agent.runtime_timing_duration_ms"
const metricValidationTrivialChangeAssessment = "agent.validation.trivial_change.assessment"
const metricValidationTrivialChangeDisagreement = "agent.validation.trivial_change.disagreement"

var runtimeTimingAllowlist = map[string]struct{}{
	"launch.firewall_mkcert_install":        {},
	"launch.firewall_prepare":               {},
	"runtime.create_runtime_context":        {},
	"runtime.create_tools_and_prompt":       {},
	"runtime.fetch_job":                     {},
	"runtime.fetch_job_and_sessions_client": {},
	"runtime.get_memories":                  {},
	"runtime.hooks_pre_session":             {},
	"runtime.init_settings":                 {},
	"runtime.initial_clone":                 {},
	"runtime.start_mcp_servers":             {},
	"runtime.time_to_first_model_event":     {},
	"runtime.time_to_first_tool_call":       {},
}

// telemetryFields generates telemetry fields from a progress job event.
func (progress *ProgressJobEvent) telemetryFields() []kvp.Field {
	kvps := make([]kvp.Field, 0)

	kvps = append(kvps, kvp.String("job.update.event.kind", progress.Kind))

	if progress.Message.Role != "" {
		kvps = append(kvps, kvp.String("job.update.event.message.role", progress.Message.Role))
	}
	if progress.Message.ToolCallID != "" {
		kvps = append(kvps, kvp.String("job.update.event.message.tool_call_id", progress.Message.ToolCallID))
	}

	// Populate Response tags
	if progress.Response.Role != "" {
		kvps = append(kvps, kvp.String("job.update.event.response.role", progress.Response.Role))
	}

	// Populate responseChunk tags
	if progress.ResponseChunk.ID != "" {
		kvps = append(kvps, kvp.String("job.update.event.responseChunk.id", progress.ResponseChunk.ID))
	}
	if progress.ResponseChunk.Model != "" {
		kvps = append(kvps, kvp.String("job.update.event.responseChunk.model", progress.ResponseChunk.Model))
	}
	if progress.ResponseChunk.Object != "" {
		kvps = append(kvps, kvp.String("job.update.event.responseChunk.object", progress.ResponseChunk.Object))
	}
	if progress.ResponseChunk.Usage.CompletionTokens != 0 {
		kvps = append(kvps, kvp.Float64("job.update.event.responseChunk.usage.completion_tokens", float64(progress.ResponseChunk.Usage.CompletionTokens)))
	}
	if progress.ResponseChunk.Usage.PromptTokens != 0 {
		kvps = append(kvps, kvp.Float64("job.update.event.responseChunk.usage.prompt_tokens", float64(progress.ResponseChunk.Usage.PromptTokens)))
	}
	if progress.ResponseChunk.Usage.TotalTokens != 0 {
		kvps = append(kvps, kvp.Float64("job.update.event.responseChunk.usage.total_tokens", float64(progress.ResponseChunk.Usage.TotalTokens)))
	}
	if len(progress.ResponseChunk.Choices) > 0 {
		// Local struct to extract relevant choice data for telemetry
		type choiceTelemetry struct {
			FinishReason  string `json:"finish_reason,omitempty"`
			Role          string `json:"role,omitempty"`
			ToolCallCount int    `json:"tool_calls_count,omitempty"`
		}

		// Extract information from each choice without PII data
		choiceTelemetryData := make([]choiceTelemetry, len(progress.ResponseChunk.Choices))
		for i, choice := range progress.ResponseChunk.Choices {
			choiceTelemetryData[i] = choiceTelemetry{
				FinishReason:  choice.FinishReason,
				Role:          choice.Delta.Role,
				ToolCallCount: len(choice.Delta.Toolcalls),
			}
		}
		choicesJSON, err := json.Marshal(choiceTelemetryData)
		if err == nil {
			kvps = append(kvps, kvp.String("job.update.event.responseChunk.choices", string(choicesJSON)))
		}
	}

	// Populate Telemetry tags
	if progress.Telemetry.Event != "" {
		kvps = append(kvps, kvp.String("job.update.event.telemetry.event", progress.Telemetry.Event))
	}
	// we cant just log every value, we need to filter privacy related out from here TODO
	for key, value := range progress.Telemetry.Properties {
		kvps = append(kvps, kvp.String(fmt.Sprintf("job.update.event.telemetry.properties.%s", strings.ToLower(key)), value))
	}
	for key, value := range progress.Telemetry.Metrics {
		kvps = append(kvps, kvp.Float64(fmt.Sprintf("job.update.event.telemetry.metrics.%s", strings.ToLower(key)), value))
	}

	// Populate session logging disabled tags
	if progress.Kind == "session_logging_disabled" {
		kvps = append(kvps,
			kvp.String("job.update.event.session_logging_disabled.reason", progress.Reason),
			kvp.String("job.update.event.session_logging_disabled.request_id", progress.RequestID),
			kvp.String("job.update.event.session_logging_disabled.response_body", progress.ResponseBody),
			kvp.Int64("job.update.event.session_logging_disabled.status_code", progress.StatusCode),
		)
	}

	return kvps
}

// publishProgressTelemetry publishes a JobProgress telemetry event.
func (update JobUpdate) publishProgressTelemetry(ctx context.Context, obsv observability.Exporters, job *jobs.Job) {
	progress := &ProgressJobEvent{}
	err := obsv.HydroPbl.Publish(progress.toJobProgress(job, update))
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).
			WithFields(kvp.String("job.update.event.kind", string(update.Kind))).
			WithError(err).Error("failed to publish job_progress event")
	}
}

// toJobProgress converts job data and progress event to a hydro JobProgress event.
func (progress *ProgressJobEvent) toJobProgress(job *jobs.Job, update JobUpdate) *sweagentv0.JobProgress {
	event := &sweagentv0.JobProgress{
		Job:          telemetry.ToJob(job),
		CreatedAt:    timestamppb.New(update.CreatedAt),
		Kind:         sweagentEntitiesv0.JobUpdateKind_PROGRESS,
		ProgressKind: &progress.Kind,
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	role, ok := progress.GetRole()
	if ok {
		event.Role = &role
	}
	switch {
	case progress.ModelCall.APIID != "":
		event.ModelCallId = progress.ModelCall.APIID
	case progress.ResponseChunk.ID != "":
		event.ModelCallId = progress.ResponseChunk.ID
	default:
		for k, v := range progress.Telemetry.Properties {
			if k == "api_call_id" {
				event.ModelCallId = v
			}
		}
	}

	return event
}

type telemetryPublisher interface {
	ShouldPublishRestrictedTelemetry(ctx context.Context, actorID int64) bool
	PublishModelCallStandardEvent(ctx context.Context, job *jobs.Job, params standardevents.ModelCallParams)
}

type getTelemetryFunc[E proto.Message] = func(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) E

// publishProgressTelemetry publishes both unrestricted and restricted telemetry
// events based on the job and progress event.
func publishProgressTelemetry[E proto.Message, R proto.Message](ctx context.Context, obsv observability.Exporters, restricted telemetryPublisher, job *jobs.Job, update JobUpdate, progress *ProgressJobEvent, tel getTelemetryFunc[E], restrictedTel getTelemetryFunc[R]) {
	logger := obsv.LoggerWithTelemetry(ctx).WithFields(progress.telemetryFields()...)

	err := obsv.HydroPbl.Publish(tel(job, update, progress))
	if err != nil {
		logger.WithError(err).Error("failed to publish telemetry event")
	}

	if restricted.ShouldPublishRestrictedTelemetry(ctx, job.ActorID) {
		err := obsv.HydroPbl.Publish(restrictedTel(job, update, progress))
		if err != nil {
			logger.WithError(err).Error("failed to publish restricted telemetry event")
		}
	}
}

// publishTelemetry publishes telemetry events for a job progress update.
func (progress *ProgressJobEvent) publishTelemetry(
	ctx context.Context,
	obsv observability.Exporters,
	restricted telemetryPublisher,
	job *jobs.Job,
	update JobUpdate,
	runtimeTimingEnabled bool,
	ffClient featureflags.Client,
) {
	switch progress.Kind {
	case "telemetry":
		switch progress.Telemetry.Event {
		case "tool_call_executed":
			publishProgressTelemetry(ctx, obsv, restricted, job, update, progress, toolCall, restrictedToolCall)
			progress.statToolCall(ctx, obsv, ffClient, job)
		case "get_completion_with_tools_turn":
			progress.statCompletionWithToolsTurn(ctx, obsv)
		case "codeql-checker-completion":
			progress.statCodeQLCheckerCompletion(ctx, obsv)
		case "mcp_server_setup":
			progress.statMCPServerSetup(ctx, obsv)
		case "timing":
			if runtimeTimingEnabled {
				progress.statRuntimeTiming(ctx, obsv)
			}
		default: // nothing to do
		}
	case "model_call_failure", "model_call_success":
		publishProgressTelemetry(ctx, obsv, restricted, job, update, progress, modelCall, restrictedModelCall)
		progress.publishModelCallStandardEvent(ctx, restricted, job, update)
	default: // nothing to do
	}

	if progress.Telemetry.Event != "" {
		publishProgressTelemetry(ctx, obsv, restricted, job, update, progress, event, restrictedEvent)
	}
}

// modelCall converts job and progress event data to a ModelCall telemetry event
func modelCall(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.ModelCall {
	e := &sweagentv0.ModelCall{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		CreatedAt:    timestamppb.New(update.CreatedAt),
		ApiCreatedAt: timestamppb.New(time.Unix(progress.ResponseChunk.Created, 0)),
		DurationMs:   progress.ModelCallDurationMs,
	}
	if progress.ResponseChunk.ID != "" {
		e.ApiId = progress.ResponseChunk.ID
		e.Model = progress.ResponseChunk.Model
		e.CompletionTokensCount = progress.ResponseChunk.Usage.CompletionTokens
		e.PromptTokensCount = progress.ResponseChunk.Usage.PromptTokens
		e.TotalTokensCount = progress.ResponseChunk.Usage.TotalTokens
		e.DurationMs = progress.ModelCallDurationMs
	} else {
		e.Model = progress.ModelCall.Model
		e.DurationMs = progress.ModelCallDurationMs
		e.RequestId = progress.ModelCall.RequestID
		e.Status = progress.ModelCall.Status
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		e.ExpAssignmentContext = job.Experiments.AssignmentContext
	}

	for _, choice := range progress.ResponseChunk.Choices {
		if len(choice.Delta.Toolcalls) > 0 {
			e.ToolCallsCount = int64(len(choice.Delta.Toolcalls))
			break // there is only ever one choice with tool calls
		}
	}

	return e
}

// publishModelCallStandardEvent extracts model call params from the progress event
// and delegates to the telemetry publisher for standard event emission.
func (progress *ProgressJobEvent) publishModelCallStandardEvent(ctx context.Context, publisher telemetryPublisher, job *jobs.Job, update JobUpdate) {
	params := standardevents.ModelCallParams{
		DurationMs:   progress.ModelCallDurationMs,
		OccurredAt:   update.CreatedAt,
		ProgressKind: progress.Kind,
		StatusCode:   progress.ModelCall.Status,
		RequestID:    progress.ModelCall.RequestID,
	}

	if publisher.ShouldPublishRestrictedTelemetry(ctx, job.ActorID) {
		params.Error = progress.ModelCall.Error
	}

	if progress.ResponseChunk.ID != "" {
		params.APIID = progress.ResponseChunk.ID
		params.Model = progress.ResponseChunk.Model
		params.CompletionTokens = progress.ResponseChunk.Usage.CompletionTokens
		params.PromptTokens = progress.ResponseChunk.Usage.PromptTokens
		params.TotalTokens = progress.ResponseChunk.Usage.TotalTokens
		for _, choice := range progress.ResponseChunk.Choices {
			if len(choice.Delta.Toolcalls) > 0 {
				params.ToolCallsCount = int64(len(choice.Delta.Toolcalls))
				break
			}
		}
	} else {
		params.APIID = progress.ModelCall.APIID
		params.Model = progress.ModelCall.Model
	}

	publisher.PublishModelCallStandardEvent(ctx, job, params)
}

// restrictedModelCall converts job and progress event data to a RestrictedModelCall telemetry event
func restrictedModelCall(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.RestrictedModelCall {
	e := &sweagentv0.RestrictedModelCall{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		CreatedAt:    timestamppb.New(update.CreatedAt),
		ApiCreatedAt: timestamppb.New(time.Unix(progress.ResponseChunk.Created, 0)),
		DurationMs:   progress.ModelCallDurationMs,
		Messages:     progress.RequestMessages,
	}

	if progress.ResponseChunk.ID != "" {
		e.ApiId = progress.ResponseChunk.ID
		e.Model = progress.ResponseChunk.Model
		e.CompletionTokensCount = progress.ResponseChunk.Usage.CompletionTokens
		e.PromptTokensCount = progress.ResponseChunk.Usage.PromptTokens
		e.TotalTokensCount = progress.ResponseChunk.Usage.TotalTokens
	} else {
		e.Model = progress.ModelCall.Model
		e.RequestId = progress.ModelCall.RequestID
		e.Status = progress.ModelCall.Status
		e.Error = progress.ModelCall.Error
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		e.ExpAssignmentContext = job.Experiments.AssignmentContext
	}

	choices := []*sweagentEntitiesv0.ModelChoice{}
	for _, responseChoice := range progress.ResponseChunk.Choices {
		choice := sweagentEntitiesv0.ModelChoice{FinishReason: responseChoice.FinishReason, Content: responseChoice.Delta.Content, Refusal: responseChoice.Delta.Refusal}
		toolCallIDs := []string{}
		toolCalls := []*sweagentEntitiesv0.ModelChoiceToolCall{}
		for _, toolcall := range responseChoice.Delta.Toolcalls {
			if toolcall.ID != "" {
				toolCallIDs = append(toolCallIDs, toolcall.ID)

				toolCalls = append(toolCalls, &sweagentEntitiesv0.ModelChoiceToolCall{
					ToolCallId: toolcall.ID,
					ToolName:   toolcall.Function.Name,
					Arguments:  toolcall.Function.Arguments,
				})
			}
		}
		choice.ToolCallIds = toolCallIDs
		choice.ToolCalls = toolCalls
		choices = append(choices, &choice)
		if len(responseChoice.Delta.Toolcalls) > 0 {
			e.ToolCallsCount = int64(len(responseChoice.Delta.Toolcalls))
		}
	}

	e.Choice = choices

	return e
}

// event converts job data and progress event to a hydro Telemetry event.
func event(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.Telemetry {
	event := &sweagentv0.Telemetry{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		Kind:         progress.Telemetry.Event,
		CreatedAt:    timestamppb.New(update.CreatedAt),
		Properties:   progress.Telemetry.Properties,
		Metrics:      progress.Telemetry.Metrics,
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	for k, v := range progress.Telemetry.Properties {
		if k == "api_call_id" {
			event.ModelCallId = v
		}
	}
	return event
}

// restrictedEvent converts job data and progress event to a hydro RestrictedTelemetry event.
func restrictedEvent(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.RestrictedTelemetry {
	event := &sweagentv0.RestrictedTelemetry{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		Kind:         progress.Telemetry.Event,
		CreatedAt:    timestamppb.New(update.CreatedAt),
		Metrics:      progress.Telemetry.Metrics,
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	for k, v := range progress.Telemetry.Properties {
		if k == "api_call_id" {
			event.ModelCallId = v
		}
	}
	// Create a new map to hold combined properties
	completeProperties := make(map[string]string)

	maps.Copy(completeProperties, progress.Telemetry.Properties)
	maps.Copy(completeProperties, progress.Telemetry.RestrictedProperties)

	event.Properties = completeProperties
	return event
}

// toolCall converts job data and progress event to a hydro ToolCall event.
func toolCall(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.ToolCall {
	event := &sweagentv0.ToolCall{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		ModelCallId:  "",
		CreatedAt:    timestamppb.New(update.CreatedAt),
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	for k, v := range progress.Telemetry.Properties {
		if k == "resultType" && v == "success" {
			event.ResultType = sweagentEntitiesv0.ToolResultType_SUCCESS
		} else if k == "resultType" && v == "failure" {
			event.ResultType = sweagentEntitiesv0.ToolResultType_FAILURE
		}
		if k == "toolName" {
			event.ToolName = v
		}
		if k == "toolCallId" {
			event.ToolCallId = v
		}
		if k == "api_call_id" {
			event.ModelCallId = v
		}
	}

	for k, v := range progress.Telemetry.Metrics {
		if k == "durationMs" {
			event.DurationMs = int64(v)
		}
	}
	return event
}

// restrictedToolCall converts job data and progress event to a hydro RestrictedToolCall event.
func restrictedToolCall(job *jobs.Job, update JobUpdate, progress *ProgressJobEvent) *sweagentv0.RestrictedToolCall {
	event := &sweagentv0.RestrictedToolCall{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		ModelCallId:  "",
		CreatedAt:    timestamppb.New(update.CreatedAt),
		Content:      "",
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		event.ExpAssignmentContext = job.Experiments.AssignmentContext
	}
	for k, v := range progress.Telemetry.Properties {
		if k == "resultType" && v == "success" {
			event.ResultType = sweagentEntitiesv0.ToolResultType_SUCCESS
		} else if k == "resultType" && v == "failure" {
			event.ResultType = sweagentEntitiesv0.ToolResultType_FAILURE
		}
		if k == "toolName" {
			event.ToolName = v
		}
		if k == "toolCallId" {
			event.ToolCallId = v
		}
		if k == "api_call_id" {
			event.ModelCallId = v
		}
	}

	for k, v := range progress.Telemetry.RestrictedProperties {
		if k == "arguments" {
			event.Arguments = v
		}
		// If the tool is not a 1P integration, the unrestricted toolname is obfuscated,
		if k == "toolName" {
			event.ToolName = v
		}
		if k == "error" {
			event.Error = v
		}
		if k == "result" {
			event.Content = v
		}
	}

	for k, v := range progress.Telemetry.Metrics {
		if k == "durationMs" {
			event.DurationMs = int64(v)
		}
	}

	return event
}

// validationTools is the set of tool names that receive the parallel_validation
// and trivial_change* metric tags.
var validationTools = map[string]struct{}{
	"code_review":         {},
	"codeql_checker":      {},
	"parallel_validation": {},
}

func isValidationTool(name string) bool {
	_, ok := validationTools[name]
	return ok
}

type validationTrivialChangeSource struct {
	toolName string
	prefix   string
}

func validationTrivialChangeSources(toolName string) []validationTrivialChangeSource {
	switch toolName {
	case "code_review":
		return []validationTrivialChangeSource{{toolName: "code_review", prefix: "trivialChange"}}
	case "codeql_checker":
		return []validationTrivialChangeSource{{toolName: "codeql_checker", prefix: "trivialChange"}}
	case "parallel_validation":
		return []validationTrivialChangeSource{
			{toolName: "code_review", prefix: "trivialChange.codeReview"},
			{toolName: "codeql_checker", prefix: "trivialChange.codeQL"},
		}
	default:
		return nil
	}
}

func (progress *ProgressJobEvent) telemetryProperty(key string) (string, bool) {
	if value, ok := progress.Telemetry.RestrictedProperties[key]; ok {
		return value, true
	}
	if value, ok := progress.Telemetry.Properties[key]; ok {
		return value, true
	}
	return "", false
}

func normalizeBoolTag(value string) string {
	switch strings.ToLower(value) {
	case "true":
		return "true"
	case "false":
		return "false"
	default:
		return "unknown"
	}
}

func alertCountTag(value string) string {
	count, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return "unknown"
	}
	if count > 0 {
		return "true"
	}
	return "false"
}

func (progress *ProgressJobEvent) statValidationTrivialChange(obsv observability.Exporters, tags stats.Tags, toolName string) {
	for _, source := range validationTrivialChangeSources(toolName) {
		isTrivial, ok := progress.telemetryProperty(source.prefix + ".isTrivial")
		if !ok {
			continue
		}

		disagreement := "false"
		if value, ok := progress.telemetryProperty(source.prefix + ".disagreement"); ok {
			disagreement = value
		}

		alertsFound := "unknown"
		if value, ok := progress.telemetryProperty(source.prefix + ".alertCount"); ok {
			alertsFound = alertCountTag(value)
		}

		metricTags := tags.Merge(stats.Tags{
			"validation_tool":             source.toolName,
			"trivial_change_is_trivial":   normalizeBoolTag(isTrivial),
			"trivial_change_disagreement": normalizeBoolTag(disagreement),
			"trivial_change_alerts_found": alertsFound,
		})

		obsv.Statter.Counter(metricValidationTrivialChangeAssessment, metricTags, 1)
		if normalizeBoolTag(disagreement) == "true" {
			obsv.Statter.Counter(metricValidationTrivialChangeDisagreement, metricTags, 1)
		}
	}
}

// allowedSkipReasons is the set of known low-cardinality skip reason values.
// Unknown values are dropped to prevent tag cardinality explosion in Datadog.
var allowedSkipReasons = map[string]struct{}{
	"budget_exhausted": {},
	"circuit_breaker":  {},
	"no_changes":       {},
	"trivial_change":   {},
}

// validSkipReason returns the skip reason from the given telemetry property
// if it is present and in the allowlist. Returns ("", false) otherwise.
func validSkipReason(properties map[string]string, key string) (string, bool) {
	reason, ok := properties[key]
	if !ok {
		return "", false
	}
	if _, allowed := allowedSkipReasons[reason]; !allowed {
		return "", false
	}
	return reason, true
}

func (progress *ProgressJobEvent) statToolCall(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, job *jobs.Job) {
	tags := obsv.TelemetryTags(ctx)
	toolName := "unknown"
	if name, ok := progress.Telemetry.Properties["toolName"]; ok {
		toolName = name
	}
	toolResult := "unknown"
	if result, ok := progress.Telemetry.Properties["resultType"]; ok {
		toolResult = result
	}

	tags = tags.Merge(stats.Tags{
		"tool.result": toolResult, "tool.name": toolName,
	})

	// Tag validation tools with the effective parallel_validation and trivial_change states
	// so duration can be filtered/grouped by execution mode in dashboards.
	// Flags are resolved lazily here to avoid the lookup on every progress callback.
	if isValidationTool(toolName) {
		enabled := ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentParallelValidation, job) &&
			!ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentParallelValidationDisabled, job)

		trivialChange := ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChange, job) &&
			!ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeDisable, job)
		trivialChangeSkip := trivialChange &&
			ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeSkip, job) &&
			!ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeSkipDisable, job)
		trivialChangeCodeReview := trivialChange &&
			ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeCodeReview, job) &&
			!ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeCodeReviewDisable, job)
		trivialChangeSkipCodeReview := trivialChangeSkip && trivialChangeCodeReview &&
			ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview, job)

		tags = tags.Merge(stats.Tags{
			"parallel_validation":             fmt.Sprintf("%t", enabled),
			"trivial_change":                  fmt.Sprintf("%t", trivialChange),
			"trivial_change_skip":             fmt.Sprintf("%t", trivialChangeSkip),
			"trivial_change_code_review":      fmt.Sprintf("%t", trivialChangeCodeReview),
			"trivial_change_skip_code_review": fmt.Sprintf("%t", trivialChangeSkipCodeReview),
		})

		progress.statValidationTrivialChange(obsv, tags, toolName)

		// Tag with skip reason when a validation tool was skipped.
		// The tag is omitted (not set to empty) when the tool ran normally.
		// Only allowed values are emitted to prevent tag cardinality explosion.
		props := progress.Telemetry.Properties
		switch toolName {
		case "parallel_validation":
			if reason, ok := validSkipReason(props, "validation.codeQL.skipReason"); ok {
				tags = tags.Merge(stats.Tags{"codeql_skip_reason": reason})
			}
			if reason, ok := validSkipReason(props, "validation.codeReview.skipReason"); ok {
				tags = tags.Merge(stats.Tags{"code_review_skip_reason": reason})
			}
		case "codeql_checker":
			if reason, ok := validSkipReason(props, "codeql.skipReason"); ok {
				tags = tags.Merge(stats.Tags{"skip_reason": reason})
			}
		case "code_review":
			if reason, ok := validSkipReason(props, "codeReview.skipReason"); ok {
				tags = tags.Merge(stats.Tags{"skip_reason": reason})
			}
		default:
		}
	}

	// Publish stats to Datadog
	durationMs, ok := progress.Telemetry.Metrics["durationMs"]
	if !ok {
		// We do not expect durationMs to be missing, but if it is, we set it to 0
		// We can track durations of 0 in Datadog
		durationMs = 0
	}
	obsv.Statter.DistributionMs(
		"agent.tool_call_duration_ms",
		tags,
		time.Duration(durationMs)*time.Millisecond,
	)
}

// statCodeQLCheckerCompletion stats various metrics about a CodeQL checker completion
// such as database creation success, analysis success, and their respective durations.
func (progress *ProgressJobEvent) statCodeQLCheckerCompletion(ctx context.Context, obsv observability.Exporters) {
	tags := obsv.TelemetryTags(ctx)
	codeqlLanguage := "unknown"
	if lang, ok := progress.Telemetry.Properties["codeql.language"]; ok {
		codeqlLanguage = lang
	}
	tags = tags.Merge(stats.Tags{
		"codeql.language": codeqlLanguage,
	})

	// Record if the CodeQL run timed out
	aborted, ok := progress.Telemetry.Properties["codeql.aborted"]
	if !ok {
		aborted = "false"
	}
	tags = tags.Merge(stats.Tags{
		"codeql.aborted": aborted,
	})

	// Publish stats to Datadog
	if codeqlDatabaseCreationSuccess, ok := progress.Telemetry.Properties["codeql.databaseCreationSuccess"]; ok {
		if codeqlDatabaseCreationSuccess == "true" {
			obsv.Statter.Counter("codeql.databaseCreationSuccess", tags, 1)
		} else {
			obsv.Statter.Counter("codeql.databaseCreationFailure", tags, 1)
		}
	}
	if codeqlDatabaseCreationTimeMs, ok := progress.Telemetry.Metrics["codeql.databaseCreationTimeMs"]; ok {
		obsv.Statter.DistributionMs(
			"codeql.databaseCreationTimeMs",
			tags,
			time.Duration(codeqlDatabaseCreationTimeMs)*time.Millisecond,
		)
	}
	if codeqlAnalysisSuccess, ok := progress.Telemetry.Properties["codeql.analysisSuccess"]; ok {
		if codeqlAnalysisSuccess == "true" {
			obsv.Statter.Counter("codeql.analysisSuccess", tags, 1)
		} else {
			obsv.Statter.Counter("codeql.analysisFailure", tags, 1)
		}
	}
	if codeqlAnalysisTimeMs, ok := progress.Telemetry.Metrics["codeql.analysisTimeMs"]; ok {
		obsv.Statter.DistributionMs(
			"codeql.analysisTimeMs",
			tags,
			time.Duration(codeqlAnalysisTimeMs)*time.Millisecond,
		)
	}
}

// statCompletionWithToolsTurn stats various metrics about a completion with tools turn
// such as number of images processed, resized, removed due to size or dimensions,
// and images sent to the LLM.
func (progress *ProgressJobEvent) statCompletionWithToolsTurn(ctx context.Context, obsv observability.Exporters) {
	tags := obsv.TelemetryTags(ctx)

	// Publish stats to Datadog
	if base64ImagesCount, ok := progress.Telemetry.Metrics["base64ImagesCount"]; ok {
		obsv.Statter.Counter("agent.vision.images_as_base64_count", tags, int64(base64ImagesCount))

		for i := range int(base64ImagesCount) {
			imageName := fmt.Sprintf("base64ImageSize_%d", i)
			if imageSize, ok := progress.Telemetry.Metrics[imageName]; ok {
				obsv.Statter.Distribution("agent.vision.base64_image_size", tags, imageSize)
			}
		}

		if progress.Kind == "session_logging_disabled" {
			tags := obsv.TelemetryTags(ctx).Merge(stats.Tags{
				"status_code": fmt.Sprintf("%d", progress.StatusCode),
			})

			obsv.Statter.Counter("agent.session_logging_disabled", tags, 1)
		}
	}
	if extractedImagesCount, ok := progress.Telemetry.Metrics["imagesExtractedCount"]; ok {
		obsv.Statter.Counter("agent.vision.images_extracted_count", tags, int64(extractedImagesCount))

		for i := range int(extractedImagesCount) {
			imageName := fmt.Sprintf("extractedImageSize_%d", i)
			if imageSize, ok := progress.Telemetry.Metrics[imageName]; ok {
				obsv.Statter.Distribution("agent.vision.extracted_image_size", tags, imageSize)
			}
		}
	}
	if imagesResolvedFromGitHubMCPCount, ok := progress.Telemetry.Metrics["imagesResolvedFromGitHubMCPCount"]; ok {
		obsv.Statter.Counter("agent.vision.images_resolved_from_github_mcp_count", tags, int64(imagesResolvedFromGitHubMCPCount))

		for i := range int(imagesResolvedFromGitHubMCPCount) {
			imageName := fmt.Sprintf("imagesResolvedFromGitHubMCPSize_%d", i)
			if imageSize, ok := progress.Telemetry.Metrics[imageName]; ok {
				obsv.Statter.Distribution("agent.vision.images_resolved_from_github_mcp_size", tags, imageSize)
			}
		}
	}

	if imagesSendToLlm, ok := progress.Telemetry.Metrics["allImagesSendToLlm"]; ok {
		obsv.Statter.Counter("agent.vision.images_passed_to_llm", tags, int64(imagesSendToLlm))
	}
	if imagesRemovedDueToSize, ok := progress.Telemetry.Metrics["imagesRemovedDueToSize"]; ok {
		obsv.Statter.Counter("agent.vision.images_removed_due_to_size", tags, int64(imagesRemovedDueToSize))
	}
	if imagesRemovedDueToDimensions, ok := progress.Telemetry.Metrics["imagesRemovedDueToDimensions"]; ok {
		obsv.Statter.Counter("agent.vision.images_removed_due_to_dimensions", tags, int64(imagesRemovedDueToDimensions))
	}
	if imagesResized, ok := progress.Telemetry.Metrics["imagesResized"]; ok {
		obsv.Statter.Counter("agent.vision.images_resized", tags, int64(imagesResized))
	}
	if imagesWithLoweredQuality, ok := progress.Telemetry.Metrics["imagesWithLoweredQuality"]; ok {
		obsv.Statter.Counter("agent.vision.images_with_lowered_quality", tags, int64(imagesWithLoweredQuality))
	}
	if resizeErrorsUnsupportedMimeType, ok := progress.Telemetry.Metrics["resizeErrorsUnsupportedMimeType"]; ok {
		obsv.Statter.Counter("agent.vision.resize_errors_unsupported_mime_type", tags, int64(resizeErrorsUnsupportedMimeType))
	}
	if resizeErrorsUnknown, ok := progress.Telemetry.Metrics["resizeErrorsUnknown"]; ok {
		obsv.Statter.Counter("agent.vision.resize_errors_unknown", tags, int64(resizeErrorsUnknown))
	}
}

// statMCPServerSetup stats various metrics about MCP server setup attempts
// such as success status and setup duration.
func (progress *ProgressJobEvent) statMCPServerSetup(ctx context.Context, obsv observability.Exporters) {
	tags := obsv.TelemetryTags(ctx)

	serverName := "unknown"
	if name, ok := progress.Telemetry.Properties["serverName"]; ok {
		serverName = name
	}

	success := "unknown"
	if result, ok := progress.Telemetry.Properties["success"]; ok {
		success = result
	}

	isDefaultServer := "unknown"
	if result, ok := progress.Telemetry.Properties["isDefaultServer"]; ok {
		isDefaultServer = result
	}

	tags = tags.Merge(stats.Tags{
		"server_name": serverName,
		"is_default":  isDefaultServer,
		"success":     success,
	})

	obsv.Statter.Counter("agent.mcp_server_setup", tags, 1)

	if durationMs, ok := progress.Telemetry.Metrics["setupDurationMs"]; ok {
		obsv.Statter.DistributionMs(
			"agent.mcp_server_setup_duration_ms",
			tags,
			time.Duration(durationMs)*time.Millisecond,
		)
	}
}

func (progress *ProgressJobEvent) statRuntimeTiming(ctx context.Context, obsv observability.Exporters) {
	name, ok := progress.Telemetry.Properties["name"]
	if !ok || name == "" {
		return
	}
	if _, allowed := runtimeTimingAllowlist[name]; !allowed {
		obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("timing.name", name)).Warn("runtime timing name is not allowlisted")
		return
	}

	durationMs, ok := progress.Telemetry.Metrics["durationMs"]
	if !ok {
		return
	}

	success := progress.Telemetry.Properties["success"]
	emitRuntimeTimingDistribution(ctx, obsv, name, success, durationMs)
}

func emitRuntimeTimingDistribution(
	ctx context.Context,
	obsv observability.Exporters,
	name, success string,
	durationMs float64,
) {
	tags := obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"timing.name": name,
	})
	if success != "" {
		tags["timing.success"] = success
	}

	obsv.Statter.DistributionMs(
		metricRuntimeTimingDurationMs,
		tags,
		time.Duration(durationMs)*time.Millisecond,
	)
}
