package processor

import (
	"context"
	"strings"
	"testing"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/dbtest"
	v210turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"

	"github.com/github/turboscan/ts/limits"
	"github.com/stretchr/testify/require"
)

func TestLogSarifStats(t *testing.T) {
	logSarifStats(context.Background(), &v210turboscan.SARIF{Runs: []*v210turboscan.Run{
		{},
	}})
}

func TestRejectLargeSarif(t *testing.T) {
	table := limits.LimitsDefault()
	stats := sarifMaxStats{ResPerRun: 100 * 1000}
	rejection := rejectLargeSarif(stats, &table)
	require.NotNil(t, rejection)

	stats = sarifMaxStats{ResPerRun: 1000}
	rejection = rejectLargeSarif(stats, &table)
	require.Nil(t, rejection)
}

func TestSarifCategory(t *testing.T) {
	// No ID cases, should take analysis key and env into account
	require.EqualValues(t, "", sarifCategory("", "", ts.AnalysisEnv{}))
	require.EqualValues(t, "", sarifCategory("", "(default)", ts.AnalysisEnv{})) // API
	require.EqualValues(t, "abc", sarifCategory("", "abc", ts.AnalysisEnv{}))
	require.EqualValues(t, "abc/language:javascript", sarifCategory("", "abc", ts.AnalysisEnv{"language": "javascript"}))
	require.EqualValues(t, "abc/language:javascript/os:linux", sarifCategory("", "abc", ts.AnalysisEnv{"language": "javascript", "os": "linux"}))
	require.EqualValues(t, "abc/language:javascript/os:linux", sarifCategory("", "abc", ts.AnalysisEnv{"os": "linux", "language": "javascript"}))

	// ID exists cases
	require.EqualValues(t, "", sarifCategory("/", "", ts.AnalysisEnv{}).String())
	require.EqualValues(t, "", sarifCategory("abc", "", ts.AnalysisEnv{}).String())
	require.EqualValues(t, "abc", sarifCategory("abc/", "", ts.AnalysisEnv{}).String())
	require.EqualValues(t, "abc", sarifCategory("abc/def", "", ts.AnalysisEnv{}).String())
	require.EqualValues(t, "abc/def", sarifCategory("abc/def/", "", ts.AnalysisEnv{}).String())

	// Truncate long categories to 1000
	longID := string(make([]byte, 4000)) + "/"
	require.Equal(t, 1000, len(sarifCategory(longID, "", ts.AnalysisEnv{})))
}

func TestSarifRunID(t *testing.T) {
	// No ID cases, should all be empty
	require.Equal(t, "", sarifRunID("", "", ts.AnalysisEnv{}))
	require.Equal(t, "", sarifRunID("", "(default)", ts.AnalysisEnv{})) // API
	require.Equal(t, "", sarifRunID("", "abc", ts.AnalysisEnv{}))
	require.Equal(t, "", sarifRunID("", "abc", ts.AnalysisEnv{"language": "javascript"}))
	require.Equal(t, "", sarifRunID("", "abc", ts.AnalysisEnv{"language": "javascript", "os": "linux"}))
	require.Equal(t, "", sarifRunID("", "abc", ts.AnalysisEnv{"os": "linux", "language": "javascript"}))

	// ID exists cases
	require.Equal(t, "", sarifRunID("/", "", ts.AnalysisEnv{}))
	require.Equal(t, "abc", sarifRunID("abc", "", ts.AnalysisEnv{}))
	require.Equal(t, "", sarifRunID("abc/", "", ts.AnalysisEnv{}))
	require.Equal(t, "def", sarifRunID("abc/def", "", ts.AnalysisEnv{}))
	require.Equal(t, "", sarifRunID("abc/def/", "", ts.AnalysisEnv{}))

	// Truncate long IDs to 250
	longID := "/" + string(make([]byte, 4000))
	require.Equal(t, 250, len(sarifRunID(longID, "", ts.AnalysisEnv{})))
}

func sarifCategory(sarifID string, analysisKey ts.AnalysisKey, env ts.AnalysisEnv) ts.Category {
	automationID := readAutomationID(context.Background(), &v210turboscan.Run{AutomationDetails: &v210turboscan.RunAutomationDetails{Id: sarifID}}, analysisKey, env)
	return automationID.Category
}

func sarifRunID(sarifID string, analysisKey ts.AnalysisKey, env ts.AnalysisEnv) string {
	automationID := readAutomationID(context.Background(), &v210turboscan.Run{AutomationDetails: &v210turboscan.RunAutomationDetails{Id: sarifID}}, analysisKey, env)
	return automationID.RunID
}

// TestDBFailureNoRetry tests that we do not excessively retry analysis processing when baseline
// have grown too large to fetch.
// See https://github.com/github/code-scanning/issues/7201 for details.
func TestDBFailureNoRetry(t *testing.T) {

	failingDB := dbtest.FailingDB{
		TargetErr:  errors.New("error processing Delivery: fetching physical alerts has failed: Error 1153: target: turboscan_ks.0.primary: vttablet: rpc error: code = ResourceExhausted desc = grpc: trying to send message larger than max (67676355 vs. 67108864)"),
		TotalCount: 1,
		QueryPred: func(query string) bool {
			return strings.Contains(query, "ts_physical_alerts")
		},
	}
	db := failingDB.RequireBadConnection(t)
	e := requireTestEnv(t, db)
	cfg := testConfig{repositoryID: 1, ref: "refs/heads/main"}

	// We deliver two analyses as we only fetch physical alerts when there is a baseline.
	_ = e.deliverSARIF(cfg, "../sarif/testdata/empty.sarif")
	analyses := e.deliverSARIFMultiple(cfg, "../sarif/testdata/empty.sarif")

	// Nothing succeeded
	require.Empty(t, analyses)

	// Check that the processing error was successfully registered
	var pe ts.ProcessError
	require.NoError(t, db.Find(&pe).Error)
	require.Contains(t, pe.Message, "could not fetch alerts from baseline")
	require.Equal(t, ts.ProcessErrorTypeUnrecoverableAnalysis, pe.ErrorType)
}
