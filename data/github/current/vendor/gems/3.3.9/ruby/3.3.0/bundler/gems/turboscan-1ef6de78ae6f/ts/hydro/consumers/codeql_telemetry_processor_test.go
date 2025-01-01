package consumers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/mocks"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"golang.org/x/exp/maps"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	TestRepositoryId         uint64 = 123
	TestRepoNwo                     = "mona/octocat"
	TestSarifId                     = "test_sarif_id"
	TestSarifUri                    = "codeql_telemetry.sarif"
	TestCommitOid                   = "abc1234"
	TestRef                         = "main"
	TestWorkflowRunId        uint64 = 456
	TestWorkflowRunAttempt   int64  = 1
	TestPlaintextMessage            = "maximum recursion depth exceeded while calling a Python object"
	TestSeverity                    = "error"
	TestTimestamp                   = "2023-03-13T15:03:47.468+00:00"
	TestAttributes                  = "{\"args\":[\"maximum recursion depth exceeded while calling a Python object\"],\"traceback\":[\"line1\",\"line2\",\"line3\"]}"
	TestSourceId                    = "py/diagnostics/recursion-error"
	TestSourceName                  = "Recursion error in Python extractor"
	TestToolComponentName           = "CodeQL"
	TestToolComponentVersion        = "2.14.2"
	TestCliVersion                  = "2.14.2"
	TestCategory                    = ".github/workflows/codeql-analysis.yml:analyze/language:python"
	TestJobRunUuid                  = "test-job-run-uuid"
)

func testAnalysis() *tshydro.Analysis {
	return &tshydro.Analysis{
		CommitOid:    TestCommitOid,
		Ref:          []byte(TestRef),
		RepositoryId: TestRepositoryId,
		RepoNwo:      TestRepoNwo,
		SarifId:      TestSarifId,
		SarifUri:     TestSarifUri,
		Tools: []*tshydro.Analysis_Tool{
			{
				Name: consumers.CodeqlToolName,
			},
		},
		WorkflowRunAttempt: TestWorkflowRunAttempt,
		WorkflowRunId:      TestWorkflowRunId,
	}
}

func testNotificationWithHierarchy(t *testing.T) *tssarif.NotificationWithHierarchy {
	t.Helper()

	s := samples.RequireSARIF(t, "testdata/codeql_telemetry.sarif")
	return &tssarif.NotificationWithHierarchy{
		Notification:        s.Runs[0].Invocations[0].ToolExecutionNotifications[0],
		ReportingDescriptor: s.Runs[0].Tool.Driver.Notifications[0],
		ToolComponent:       s.Runs[0].Tool.Driver,
		Run:                 s.Runs[0],
	}
}

func testTags() []string {
	return []string{}
}

func testProcessNewAnalysis(t *testing.T, toolName string, isOutdated bool, expectSarifDownload bool) {
	t.Helper()

	sarifStore := mocks.NewMockSarifStore(gomock.NewController(t))

	if expectSarifDownload {
		mockSarif := map[string]interface{}{
			"runs": []interface{}{},
		}
		sarifBytes, err := json.Marshal(mockSarif)
		require.NoError(t, err)
		sarifBuffer := bytes.NewBuffer(sarifBytes)
		sarifStore.EXPECT().Download(gomock.Any(), gomock.Any()).Return(sarifBuffer, nil).Times(1)
	} else {
		sarifStore.EXPECT().Download(gomock.Any(), gomock.Any()).Times(0)
	}

	outdatedConfig := &tshydro.Analysis_OutdatedConfiguration{}
	if isOutdated {
		outdatedConfig.Category = "test"
		outdatedConfig.ToolName = toolName
	}

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, sarifStore, nil)
	err := p.ProcessNewAnalysis(context.Background(), &tshydro.Analysis{
		OutdatedConfiguration: outdatedConfig,
		Tools: []*tshydro.Analysis_Tool{
			{
				Name: toolName,
			},
		},
	})
	require.NoError(t, err)
}

func TestProcessNewAnalysis(t *testing.T) {
	// SARIF should be downloaded when the tool referenced is CodeQL and the analysis isn't outdated.
	testProcessNewAnalysis(t, consumers.CodeqlToolName, false, true)
}

func TestProcessNewAnalysis_SkipsWhenNoCodeql(t *testing.T) {
	// SARIF shouldn't be downloaded when the analysis wasn't produced by CodeQL.
	testProcessNewAnalysis(t, "not-codeql", false, false)
}

func TestProcessNewAnalysis_SkipsWhenOutdated(t *testing.T) {
	// SARIF shouldn't be downloaded when the analysis is outdated.
	testProcessNewAnalysis(t, consumers.CodeqlToolName, true, false)
}

func TestLogTelemetryDiagnostic(t *testing.T) {
	analysis := testAnalysis()
	notificationWithHierarchy := testNotificationWithHierarchy(t)

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx := appctx.WithLogger(context.Background(), logger)

	subsequentLogger := mocks.NewMockLogger(mockCtrl)
	subsequentLogger.EXPECT().Info("CodeQL telemetry diagnostic")

	logger.EXPECT().WithFields(
		kvp.String("gh.turboscan.codeql_telemetry.timestamp", TestTimestamp),
		kvp.String("gh.turboscan.codeql_telemetry.plaintext_message", TestPlaintextMessage),
		kvp.String("gh.turboscan.codeql_telemetry.severity", TestSeverity),
		kvp.String("gh.turboscan.codeql_telemetry.attributes", TestAttributes),
		// Notification source metadata
		kvp.String("gh.turboscan.codeql_telemetry.source_id", TestSourceId),
		kvp.String("gh.turboscan.codeql_telemetry.source_name", TestSourceName),
		kvp.Strings("gh.turboscan.codeql_telemetry.tags", testTags()),
		// Tool component metadata
		kvp.String("gh.turboscan.codeql_telemetry.tool_component_name", TestToolComponentName),
		kvp.String("gh.turboscan.codeql_telemetry.tool_component_version", TestToolComponentVersion),
		// Tool metadata
		kvp.String("gh.turboscan.codeql_telemetry.cli_version", TestCliVersion),
		// Run metadata
		kvp.String("gh.turboscan.codeql_telemetry.category", TestCategory),
		kvp.String("gh.turboscan.codeql_telemetry.job_run_uuid", TestJobRunUuid),
		// Analysis metadata
		kvp.Uint64("gh.turboscan.codeql_telemetry.repository_id", TestRepositoryId),
		kvp.String("gh.turboscan.codeql_telemetry.sarif_uri", TestSarifUri),
		kvp.String("gh.turboscan.codeql_telemetry.commit_oid", TestCommitOid),
		kvp.ByteString("gh.turboscan.codeql_telemetry.ref", []byte(TestRef)),
		kvp.Uint64("gh.turboscan.codeql_telemetry.workflow_run_id", TestWorkflowRunId),
		kvp.Int64("gh.turboscan.codeql_telemetry.workflow_run_attempt", TestWorkflowRunAttempt),
	).Return(subsequentLogger)

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)
	err := p.LogTelemetryDiagnostic(ctx, analysis, notificationWithHierarchy)
	require.NoError(t, err)
}

func TestLogTelemetryDiagnosticWithoutTimestamp(t *testing.T) {
	analysis := testAnalysis()
	notificationWithHierarchy := testNotificationWithHierarchy(t)
	notificationWithHierarchy.Notification.TimeUtc = ""

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx := appctx.WithLogger(context.Background(), logger)

	subsequentLogger := mocks.NewMockLogger(mockCtrl)
	subsequentLogger.EXPECT().Info("CodeQL telemetry diagnostic")

	logger.EXPECT().WithFields(
		kvp.String("gh.turboscan.codeql_telemetry.timestamp", ""),
	).Return(subsequentLogger)

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)
	err := p.LogTelemetryDiagnostic(ctx, analysis, notificationWithHierarchy)
	require.NoError(t, err)
}

func TestConvertDiagnosticToHydro(t *testing.T) {
	analysis := testAnalysis()
	notificationWithHierarchy := testNotificationWithHierarchy(t)

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)

	expectedTimestamp, err := time.Parse(time.RFC3339, TestTimestamp)
	require.NoError(t, err)

	expectedMessage := &tshydro.CodeqlTelemetryMessage{
		RepositoryId:         TestRepositoryId,
		RepositoryNwo:        TestRepoNwo,
		CommitOid:            TestCommitOid,
		Ref:                  []byte(TestRef),
		WorkflowRunId:        TestWorkflowRunId,
		WorkflowRunAttempt:   TestWorkflowRunAttempt,
		Category:             TestCategory,
		JobRunUuid:           TestJobRunUuid,
		CodeqlVersion:        TestCliVersion,
		ToolComponentName:    TestToolComponentName,
		ToolComponentVersion: TestToolComponentVersion,
		SourceId:             TestSourceId,
		SourceName:           TestSourceName,
		Tags:                 testTags(),
		CreatedAt:            timestamppb.New(expectedTimestamp),
		PlaintextMessage:     TestPlaintextMessage,
		Severity:             TestSeverity,
		Attributes:           wrapperspb.String(TestAttributes),
	}

	actualMessage, err := p.ConvertDiagnosticToHydro(analysis, notificationWithHierarchy)
	require.NoError(t, err)
	require.Equal(t, expectedMessage, actualMessage)
}

func TestConvertDiagnosticWithoutTimestampToHydro(t *testing.T) {
	analysis := testAnalysis()
	notificationWithHierarchy := testNotificationWithHierarchy(t)
	notificationWithHierarchy.Notification.TimeUtc = ""

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)

	message, err := p.ConvertDiagnosticToHydro(analysis, notificationWithHierarchy)
	require.NoError(t, err)
	require.Nil(t, message.CreatedAt)
}

func TestConvertDiagnosticWithNonUtcTimestampToHydro(t *testing.T) {
	analysis := testAnalysis()
	notificationWithHierarchy := testNotificationWithHierarchy(t)
	notificationWithHierarchy.Notification.TimeUtc = "2024-09-16T11:54:35.701+01:00"

	expectedTimestamp, err := time.Parse(time.RFC3339, notificationWithHierarchy.Notification.TimeUtc)
	require.NoError(t, err)

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)

	message, err := p.ConvertDiagnosticToHydro(analysis, notificationWithHierarchy)
	require.NoError(t, err)
	require.Equal(t, timestamppb.New(expectedTimestamp), message.CreatedAt)
}

func TestNoCodeqlErrorWithoutInternalErrorTag(t *testing.T) {
	// This notification does not have the internal-error tag.
	notificationWithHierarchy := testNotificationWithHierarchy(t)

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)
	codeqlError := p.CreateCodeqlError(context.Background(), notificationWithHierarchy)
	require.Nil(t, codeqlError)
}

func TestCodeqlErrorWithInternalErrorTag(t *testing.T) {
	n := testNotificationWithHierarchy(t)

	n.ReportingDescriptor.Properties = &v2_1_0.ReportingDescriptorPropertyBag{
		Tags: []string{"internal-error"},
	}

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)
	codeqlError := p.CreateCodeqlError(context.Background(), n)
	require.NotNil(t, codeqlError)
	require.Equal(t, "py/diagnostics/recursion-error: Recursion error in Python extractor", codeqlError.Error())
}

func TestCodeqlErrorPayload(t *testing.T) {
	analysis := testAnalysis()
	n := testNotificationWithHierarchy(t)

	n.ReportingDescriptor.Properties = &v2_1_0.ReportingDescriptorPropertyBag{
		Tags: []string{"internal-error"},
	}

	p := consumers.NewCodeqlTelemetryProcessor(nil, nil, nil, nil)
	payload, err := p.CreateCodeqlErrorPayload(analysis, n)
	require.NoError(t, err)

	expectedKeys := []string{
		"gh.turboscan.codeql_telemetry.timestamp",
		"gh.turboscan.codeql_telemetry.severity",
		"gh.turboscan.codeql_telemetry.source_id",
		"gh.turboscan.codeql_telemetry.tags",
		"gh.turboscan.codeql_telemetry.tool_component_name",
		"gh.turboscan.codeql_telemetry.tool_component_version",
		"gh.turboscan.codeql_telemetry.cli_version",
		"gh.turboscan.codeql_telemetry.job_run_uuid",
		"gh.turboscan.codeql_telemetry.repository_id",
	}
	require.ElementsMatch(t, expectedKeys, maps.Keys(payload), "payload should only contain expected keys")

	require.Equal(t, TestTimestamp, payload["gh.turboscan.codeql_telemetry.timestamp"])
	require.Equal(t, TestSeverity, payload["gh.turboscan.codeql_telemetry.severity"])
	require.Equal(t, TestSourceId, payload["gh.turboscan.codeql_telemetry.source_id"])
	require.Equal(t, "internal-error", payload["gh.turboscan.codeql_telemetry.tags"])
	require.Equal(t, TestToolComponentName, payload["gh.turboscan.codeql_telemetry.tool_component_name"])
	require.Equal(t, TestToolComponentVersion, payload["gh.turboscan.codeql_telemetry.tool_component_version"])
	require.Equal(t, TestCliVersion, payload["gh.turboscan.codeql_telemetry.cli_version"])
	require.Equal(t, TestJobRunUuid, payload["gh.turboscan.codeql_telemetry.job_run_uuid"])
	require.Equal(t, "123", payload["gh.turboscan.codeql_telemetry.repository_id"])
}

func TestConvertMetricResultToHydro_linesOfCode(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/metrics.sarif")

	metricResult := &tssarif.MetricResultWithHierarchy{
		MetricResult: s.Runs[0].Properties.MetricResults[0],
		Rule:         s.Runs[0].Tool.Extensions[0].Rules[0],
		Run:          s.Runs[0],
	}
	hydroMessage := consumers.ConvertMetricResultToHydro(testAnalysis(), metricResult)
	require.EqualValues(t, TestRepositoryId, hydroMessage.RepositoryId)
	require.EqualValues(t, TestSarifId, hydroMessage.SarifId)
	require.EqualValues(t, "cpp/summary/lines-of-code", hydroMessage.RuleId)
	require.EqualValues(t, 202907, hydroMessage.Value)
	require.EqualValues(t, 301247, hydroMessage.Baseline.GetValue())
	require.Nil(t, hydroMessage.Message)
}

func TestConvertMetricResultToHydro_metricWithMessage(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/telemetry-java.sarif")

	metricResult := &tssarif.MetricResultWithHierarchy{
		MetricResult: s.Runs[0].Properties.MetricResults[0],
		Rule:         s.Runs[0].Tool.Extensions[0].Rules[0],
		Run:          s.Runs[0],
	}
	hydroMessage := consumers.ConvertMetricResultToHydro(testAnalysis(), metricResult)
	require.EqualValues(t, TestRepositoryId, hydroMessage.RepositoryId)
	require.EqualValues(t, TestSarifId, hydroMessage.SarifId)
	require.EqualValues(t, "java/telemetry/supported-external-api", hydroMessage.RuleId)
	require.EqualValues(t, 1, hydroMessage.Value)
	require.Nil(t, hydroMessage.Baseline)
	require.Equal(t, "java.io.PrintStream#println(String)", hydroMessage.Message.GetValue())
}
