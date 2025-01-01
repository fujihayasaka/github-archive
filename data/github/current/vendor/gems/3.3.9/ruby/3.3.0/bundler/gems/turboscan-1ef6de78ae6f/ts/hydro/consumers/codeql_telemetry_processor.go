package consumers

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/o11y"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/store"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/pkg/errors"
	"golang.org/x/exp/slices"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	// Tool name for CodeQL.
	CodeqlToolName string = "CodeQL"
)

type CodeqlMetricPublisher interface {
	CodeqlMetricResultBatch(context.Context, []*tshydro.CodeqlMetricResult) error
}

type CodeqlTelemetryPublisher interface {
	CodeqlTelemetryMessage(context.Context, *tshydro.CodeqlTelemetryMessage) error
}

// CodeqlTelemetryProcessor is responsible for processing and reacting to ProcessedAnalysis events
// containing CodeQL telemetry data.
// It implements the HydroProcessor interface.
type CodeqlTelemetryProcessor struct {
	// codeqlReporter is used to publish CodeQL internal errors to Sentry based on the data within
	// SARIF files submitted to Turboscan.
	//
	// Exceptions will be reported here during normal operation of the CodeQL telemetry processor.
	codeqlReporter     o11y.ExceptionReporter
	metricPublisher    CodeqlMetricPublisher
	sarifStore         store.SarifStore
	telemetryPublisher CodeqlTelemetryPublisher
}

// Verify that CodeqlTelemetryProcessor implements the HydroProcessor interface
var _ hydroProcessor = (*CodeqlTelemetryProcessor)(nil)

func (p *CodeqlTelemetryProcessor) ProcessNewAnalysis(ctx context.Context, analysis *tshydro.Analysis) error {

	if analysis.OutdatedConfiguration != nil && analysis.OutdatedConfiguration.Category != "" || analysis.OutdatedConfiguration.ToolName != "" {
		appctx.Logger(ctx).Debug("Skipping outdated analysis")
		return nil
	}

	if !analysisIncludesCodeql(analysis) {
		appctx.Logger(ctx).Debug("Skipping analysis that does not include CodeQL")
		return nil
	}

	// Retrieve the SARIF
	buf, err := p.sarifStore.Download(ctx, analysis.SarifUri)
	if err != nil {
		return errors.Wrap(err, "failed to download SARIF file")
	}

	// Parse the SARIF
	sarif, err := tssarif.Decode(buf.Bytes())
	if err != nil {
		return errors.Wrap(err, "failed to parse SARIF file")
	}

	// Get the telemetry diagnostics
	diagnostics, err := tssarif.GetCodeqlTelemetryDiagnostics(ctx, sarif)
	if err != nil {
		return errors.Wrap(err, "failed to get telemetry diagnostics from SARIF")
	}

	appctx.Logger(ctx).Debug(
		"Successfully parsed telemetry diagnostics from SARIF",
		kvp.Int("gh.turboscan.codeql_telemetry.num_diagnostics", len(diagnostics)),
	)

	// Process the telemetry diagnostics
	for _, diagnostic := range diagnostics {
		err = p.processTelemetryDiagnostic(ctx, analysis, diagnostic)
		if err != nil {
			return errors.Wrap(err, "failed to process telemetry diagnostic")
		}
	}

	appctx.Stats(ctx).Counter("codeqltelemetry.processed_messages", stats.Tags{}, int64(len(diagnostics)))

	err = p.processMetricResults(ctx, analysis, sarif)
	if err != nil {
		return errors.Wrap(err, "failed to process metric results")
	}

	appctx.Stats(ctx).Counter("codeqltelemetry.status", stats.Tags{"success": "true"}, 1)

	return nil
}

func (p *CodeqlTelemetryProcessor) processTelemetryDiagnostic(ctx context.Context, analysis *tshydro.Analysis, notification *tssarif.NotificationWithHierarchy) error {
	err := p.LogTelemetryDiagnostic(ctx, analysis, notification)
	if err != nil {
		return errors.Wrap(err, "failed to log telemetry diagnostic to Splunk")
	}
	appctx.Logger(ctx).Debug("Logged telemetry diagnostic to Splunk")

	hydroMessage, err := p.ConvertDiagnosticToHydro(analysis, notification)
	if err != nil {
		return errors.Wrap(err, "failed to convert telemetry diagnostic to Hydro message")
	}

	err = p.telemetryPublisher.CodeqlTelemetryMessage(ctx, hydroMessage)
	if err != nil {
		return errors.Wrap(err, "failed to send telemetry diagnostic to Hydro")
	}

	appctx.Logger(ctx).Debug("Sent telemetry diagnostic to Hydro")

	codeqlError := p.CreateCodeqlError(ctx, notification)
	if codeqlError != nil {
		payload, err := p.CreateCodeqlErrorPayload(analysis, notification)
		if err != nil {
			return errors.Wrap(err, "failed to create CodeQL error payload")
		}
		err = p.codeqlReporter.Report(ctx, codeqlError, payload)
		if err != nil {
			return errors.Wrap(err, "failed to report CodeQL error to Sentry")
		}

		appctx.Logger(ctx).Debug("Reported CodeQL error to Sentry")
	}

	return nil
}

func (p *CodeqlTelemetryProcessor) ConvertDiagnosticToHydro(analysis *tshydro.Analysis, n *tssarif.NotificationWithHierarchy) (*tshydro.CodeqlTelemetryMessage, error) {
	notification := n.Notification
	reportingDescriptor := n.ReportingDescriptor
	toolComponent := n.ToolComponent
	run := n.Run

	var timestamp *timestamppb.Timestamp = nil
	if notification.TimeUtc != "" {
		parsedTimestamp, err := time.Parse(time.RFC3339, notification.TimeUtc)
		if err != nil {
			return nil, errors.Wrap(err, "failed to parse notification timestamp")
		}
		timestamp = timestamppb.New(parsedTimestamp)
	}

	message := ""
	if notification.Message != nil {
		message = notification.Message.Text
	}

	attributesJsonString, err := getNotificationAttributesJson(notification)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get notification attributes as a JSON string")
	}
	var attributesJson *wrapperspb.StringValue
	if attributesJsonString != "" {
		attributesJson = wrapperspb.String(attributesJsonString)
	}

	sourceName := ""
	if reportingDescriptor.ShortDescription != nil {
		sourceName = reportingDescriptor.ShortDescription.Text
	}

	tags := []string{}
	if reportingDescriptor.Properties != nil && reportingDescriptor.Properties.Tags != nil {
		tags = reportingDescriptor.Properties.Tags
	}

	toolVersion := ""
	if run.Tool != nil && run.Tool.Driver != nil {
		toolVersion = run.Tool.Driver.SemanticVersion
	}

	hydroMessage := &tshydro.CodeqlTelemetryMessage{
		// Notification metadata
		CreatedAt:        timestamp,
		PlaintextMessage: message,
		Severity:         notification.Level,
		Attributes:       attributesJson,
		// Notification source metadata
		SourceId:   reportingDescriptor.Id,
		SourceName: sourceName,
		Tags:       tags,
		// Tool component metadata
		ToolComponentName:    toolComponent.Name,
		ToolComponentVersion: toolComponent.SemanticVersion,
		// Tool metadata
		CodeqlVersion: toolVersion,
		// Run metadata
		Category:   run.AutomationID(),
		JobRunUuid: run.JobRunUuid(),
		// Analysis metadata
		RepositoryId:       analysis.RepositoryId,
		RepositoryNwo:      analysis.RepoNwo,
		CommitOid:          analysis.CommitOid,
		Ref:                analysis.Ref,
		WorkflowRunId:      analysis.WorkflowRunId,
		WorkflowRunAttempt: analysis.WorkflowRunAttempt,
	}

	return hydroMessage, nil
}

func (p *CodeqlTelemetryProcessor) LogTelemetryDiagnostic(ctx context.Context, analysis *tshydro.Analysis, n *tssarif.NotificationWithHierarchy) error {
	notification := n.Notification
	reportingDescriptor := n.ReportingDescriptor
	toolComponent := n.ToolComponent
	run := n.Run

	message := ""
	if notification.Message != nil {
		message = notification.Message.Text
	}

	attributesJson, err := getNotificationAttributesJson(notification)
	if err != nil {
		return errors.Wrap(err, "failed to get notification attributes as a JSON string")
	}

	sourceName := ""
	if reportingDescriptor.ShortDescription != nil {
		sourceName = reportingDescriptor.ShortDescription.Text
	}

	tags := []string{}
	if reportingDescriptor.Properties != nil && reportingDescriptor.Properties.Tags != nil {
		tags = reportingDescriptor.Properties.Tags
	}

	toolVersion := ""
	if run.Tool != nil && run.Tool.Driver != nil {
		toolVersion = run.Tool.Driver.SemanticVersion
	}

	appctx.Logger(ctx).WithFields(
		// Notification metadata
		kvp.String("gh.turboscan.codeql_telemetry.timestamp", notification.TimeUtc),
		kvp.String("gh.turboscan.codeql_telemetry.plaintext_message", message),
		kvp.String("gh.turboscan.codeql_telemetry.severity", notification.Level),
		kvp.String("gh.turboscan.codeql_telemetry.attributes", attributesJson),
		// Notification source metadata
		kvp.String("gh.turboscan.codeql_telemetry.source_id", reportingDescriptor.Id),
		kvp.String("gh.turboscan.codeql_telemetry.source_name", sourceName),
		kvp.Strings("gh.turboscan.codeql_telemetry.tags", tags),
		// Tool component metadata
		kvp.String("gh.turboscan.codeql_telemetry.tool_component_name", toolComponent.Name),
		kvp.String("gh.turboscan.codeql_telemetry.tool_component_version", toolComponent.SemanticVersion),
		// Tool metadata
		kvp.String("gh.turboscan.codeql_telemetry.cli_version", toolVersion),
		// Run metadata
		kvp.String("gh.turboscan.codeql_telemetry.category", run.AutomationID()),
		kvp.String("gh.turboscan.codeql_telemetry.job_run_uuid", run.JobRunUuid()),
		// Analysis metadata
		kvp.Uint64("gh.turboscan.codeql_telemetry.repository_id", analysis.RepositoryId),
		kvp.String("gh.turboscan.codeql_telemetry.sarif_uri", analysis.SarifUri),
		kvp.String("gh.turboscan.codeql_telemetry.commit_oid", analysis.CommitOid),
		kvp.ByteString("gh.turboscan.codeql_telemetry.ref", analysis.Ref),
		kvp.Uint64("gh.turboscan.codeql_telemetry.workflow_run_id", analysis.WorkflowRunId),
		kvp.Int64("gh.turboscan.codeql_telemetry.workflow_run_attempt", analysis.WorkflowRunAttempt),
	).Info("CodeQL telemetry diagnostic")

	return nil
}

// CreateCodeqlError creates an error for the CodeQL telemetry diagnostic suitable for sending to
// Sentry. Returns nil if the diagnostic is not an internal error.
//
// This must not contain any sensitive data. For more information, see
// https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/sensitive-content-filtering/
func (p *CodeqlTelemetryProcessor) CreateCodeqlError(ctx context.Context, n *tssarif.NotificationWithHierarchy) error {
	reportingDescriptor := n.ReportingDescriptor

	if reportingDescriptor.Properties == nil || reportingDescriptor.Properties.Tags == nil ||
		!slices.Contains(reportingDescriptor.Properties.Tags, "internal-error") {
		appctx.Logger(ctx).Debug("Not reporting internal error to Sentry because the notification is not tagged as an internal error")
		return nil
	}

	if reportingDescriptor.ShortDescription == nil || reportingDescriptor.ShortDescription.Text == "" {
		appctx.Logger(ctx).Warn("Not reporting internal error to Sentry because the notification does not have a source name")
		return nil
	}

	// The error message may contain potentially sensitive details, such as file paths, therefore we
	// only send information about the error source, e.g. "py/diagnostics/recursion-error: Recursion
	// error in Python extractor".
	return errors.New(reportingDescriptor.Id + ": " + reportingDescriptor.ShortDescription.Text)
}

// CreateCodeqlErrorPayload creates a payload for the CodeQL telemetry diagnostic suitable for sending to Sentry.
//
// This must not contain any sensitive data. For more information, see
// https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/sensitive-content-filtering/
func (p *CodeqlTelemetryProcessor) CreateCodeqlErrorPayload(analysis *tshydro.Analysis, n *tssarif.NotificationWithHierarchy) (map[string]string, error) {
	notification := n.Notification
	reportingDescriptor := n.ReportingDescriptor
	toolComponent := n.ToolComponent
	run := n.Run

	tags := []string{}
	if reportingDescriptor.Properties != nil && reportingDescriptor.Properties.Tags != nil {
		tags = reportingDescriptor.Properties.Tags
	}

	toolVersion := ""
	if run.Tool != nil && run.Tool.Driver != nil {
		toolVersion = run.Tool.Driver.SemanticVersion
	}

	// We must ensure that the payload does not contain any sensitive data:
	// - The repository ID and the timestamp are not sensitive data
	// - The remaining fields here take on a hardcoded set of values that's shipped with CodeQL
	payload := map[string]string{
		// Notification metadata
		"gh.turboscan.codeql_telemetry.timestamp": notification.TimeUtc,
		"gh.turboscan.codeql_telemetry.severity":  notification.Level,
		// Notification source metadata
		"gh.turboscan.codeql_telemetry.source_id": reportingDescriptor.Id,
		"gh.turboscan.codeql_telemetry.tags":      strings.Join(tags, " "),
		// Tool component metadata
		"gh.turboscan.codeql_telemetry.tool_component_name":    toolComponent.Name,
		"gh.turboscan.codeql_telemetry.tool_component_version": toolComponent.SemanticVersion,
		// Tool metadata
		"gh.turboscan.codeql_telemetry.cli_version": toolVersion,
		// Run metadata
		"gh.turboscan.codeql_telemetry.job_run_uuid": run.JobRunUuid(),
		// Analysis metadata
		"gh.turboscan.codeql_telemetry.repository_id": strconv.FormatUint(analysis.RepositoryId, 10),
	}

	return payload, nil
}

func (p *CodeqlTelemetryProcessor) Topics() []string {
	return []string{topics.ProcessedAnalysis}
}

func (p *CodeqlTelemetryProcessor) ProcessorName() string {
	return "CodeqlTelemetryProcessor"
}

func (p *CodeqlTelemetryProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {

	var msg tshydro.Analysis

	err := UnwrapAnalysisMessage(envelope.Message, &msg)
	if err != nil {
		return errors.Wrap(err, "unmarshalling analysis message")
	}

	return p.ProcessNewAnalysis(ctx, &msg)
}

func (p *CodeqlTelemetryProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	appctx.Stats(ctx).Counter("codeqltelemetry.status", stats.Tags{"success": "false"}, 1)
	return handleError(ctx, err, m)
}

func (p *CodeqlTelemetryProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *CodeqlTelemetryProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}

func (p *CodeqlTelemetryProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

func analysisIncludesCodeql(msg *tshydro.Analysis) bool {
	for _, tool := range msg.Tools {
		// Check the tool name, since the tool ID will not be stable across stamps.
		if tool.Name == CodeqlToolName {
			return true
		}
	}
	return false
}

func getNotificationAttributesJson(notification *v2_1_0.Notification) (string, error) {
	attributesJson := ""
	if notification.Properties != nil && notification.Properties.Attributes != nil && notification.Properties.Attributes.AdditionalProperties != nil {
		attributesData, err := json.Marshal(notification.Properties.Attributes.AdditionalProperties)
		if err != nil {
			return "", errors.Wrap(err, "failed to marshal notification attributes")
		}
		attributesJson = string(attributesData)
	}
	return attributesJson, nil
}

func (p *CodeqlTelemetryProcessor) processMetricResults(ctx context.Context, analysis *tshydro.Analysis, sarif *v2_1_0.SARIF) error {
	// Get the metric results
	metricResults, err := tssarif.GetCodeqlMetricResults(sarif, appctx.Logger(ctx))
	if err != nil {
		return errors.Wrap(err, "failed to get metric results from SARIF")
	}

	appctx.Logger(ctx).Debug(
		"Successfully parsed metric results from SARIF",
		kvp.Int("gh.turboscan.codeql_telemetry.num_metric_results", len(metricResults)),
	)

	if len(metricResults) == 0 {
		return nil
	}

	// Send the metric results to Hydro
	hydroMessages := []*tshydro.CodeqlMetricResult{}

	for _, metricResult := range metricResults {
		m := ConvertMetricResultToHydro(analysis, metricResult)
		hydroMessages = append(hydroMessages, m)
	}

	start := time.Now()
	err = p.metricPublisher.CodeqlMetricResultBatch(ctx, hydroMessages)
	if err != nil {
		return errors.Wrap(err, "failed to send metric results to Hydro")
	}
	appctx.Logger(ctx).Debug(
		"Published metric results to Hydro",
		kvp.Int("gh.turboscan.codeql_telemetry.num_metric_results", len(metricResults)),
		kvp.Duration("gh.turboscan.codeql_telemetry.metric_results_publish_duration", time.Since(start)),
	)

	appctx.Stats(ctx).Counter("codeqltelemetry.processed_metric_results", stats.Tags{}, int64(len(metricResults)))
	return nil
}

// ConvertMetricResultToHydro converts a CodeQL metric result as stored
// within the SARIF file to the format we use for the `CodeqlMetricResult` Hydro
// topic.
func ConvertMetricResultToHydro(analysis *tshydro.Analysis, m *tssarif.MetricResultWithHierarchy) *tshydro.CodeqlMetricResult {
	metricResult := m.MetricResult

	var baseline *wrapperspb.DoubleValue = nil
	if v, ok := metricResult.Baseline.(float64); ok {
		baseline = wrapperspb.Double(v)
	}

	var message *wrapperspb.StringValue = nil
	if metricResult.Message != nil && metricResult.Message.Text != "" {
		message = wrapperspb.String(metricResult.Message.Text)
	}

	return &tshydro.CodeqlMetricResult{
		RepositoryId: int64(analysis.RepositoryId),
		ProcessedAt:  analysis.UploadStartedAt,
		SarifId:      analysis.SarifId,
		RuleId:       m.Rule.Id,
		Value:        metricResult.Value,
		Baseline:     baseline,
		Message:      message,
	}
}

func NewCodeqlTelemetryProcessor(codeqlReporter o11y.ExceptionReporter, metricPublisher CodeqlMetricPublisher, sarifStore store.SarifStore, telemetryPublisher CodeqlTelemetryPublisher) *CodeqlTelemetryProcessor {

	return &CodeqlTelemetryProcessor{
		codeqlReporter:     codeqlReporter,
		metricPublisher:    metricPublisher,
		sarifStore:         sarifStore,
		telemetryPublisher: telemetryPublisher,
	}
}
