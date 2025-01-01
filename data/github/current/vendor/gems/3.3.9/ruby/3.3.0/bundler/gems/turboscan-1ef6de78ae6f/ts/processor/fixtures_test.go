package processor

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/indexer"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/alertlink"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/google/uuid"
	gomock "go.uber.org/mock/gomock"

	"github.com/github/turboscan/ts/mysql/managedanalysis"

	mysqlanalysis "github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/pr_alerts"

	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/gc"
	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/timeline"

	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/github/turboscan/ts/sarif/store"
	"github.com/github/turboscan/ts/transforms"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/proto"
	tssarif "github.com/github/turboscan/ts/sarif"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	hydro_schemas_code_scanning_v0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	hydro_schemas_github_security_center_v0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	hydro_schemas_turboscan_v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts/hydro/publishers"
)

// Utilities for writing tests

// testRepoID is a constant so that all tests do not need to specify it
var testRepoID = ts.RepositoryEID(191)

func testStableID(lb byte) []byte {
	return []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, lb}
}

// testEnv encapsulates all the different parts that are required for testing the calls
type testEnv struct {
	ctx             context.Context
	db              *gorm.DB
	es              *elasticsearch.Service
	t               *testing.T
	publisher       *CollectingPublisher
	as              *alert.Service
	prAlertsService *pr_alerts.Service
	ss              store.SarifStore
	analyses        *mysqlanalysis.Service
	archiveService  *archiver.Service
	ds              *delivery.Service
	gc              *gc.Service
	tss             *timeline.Service
	tools           *tool.Service
	configurations  *configuration.Service
	rs              *rule.Service
	repos           *repository.Service
	ams             *analysismessage.Service
	managedAnalysis *managedanalysis.Service
	insightsHandler ts.InsightsHydroAlertEventHandler
	jobs            aqueduct.JobPerformer
	al              *alertlinks.Service
	paGuids         map[string]string

	// commitCounter maintain the number of delivered analyses
	commitCounter int
}

type CommitBehavior uint8

const (
	CommitBehaviorNormal CommitBehavior = iota
	CommitBehaviorNone
	CommitBehaviorFail
	CommitBehaviorNoPromote
)

// testConfig contains properties used for creating analyses
// these can be left empty to use default values
type testConfig struct {
	repositoryID       ts.RepositoryEID
	ref                string
	commitOid          ts.Sha
	analysisKey        string
	tool               ts.ToolName
	toolVersion        string
	environment        map[string]string
	startTime          *time.Time
	sourceRepositoryID ts.RepositoryEID
	commitBehavior     CommitBehavior
	limitSelector      *limits.LimitSelector
}

type skipRepoSyncAPI struct {
	rs *repository.Service
}

func (api *skipRepoSyncAPI) GetRepositories(ctx context.Context, ids []ts.RepositoryEID) ([]*ts.Repository, error) {
	return api.rs.FindExisting(ctx, ids)
}

// requireTestEnv creates a test env and fails if it cannot create it
func requireTestEnv(t *testing.T, db *gorm.DB) *testEnv {
	t.Helper()
	ctx := context.Background()

	publisher := &CollectingPublisher{}

	toolService := tool.NewService(db, limits.TestLimitSelector())
	sarifStore := store.TestMemoryStore()
	require.NoError(t, sarifStore.Open(ctx))
	as := alert.TestService(db)
	archiveService := archiver.NewService(db, sarifStore, archiver.WithBatchSize(1))

	es := elasticsearch.SetUpTestElasticSearchService(t)
	insightsHandler := publishers.NewInsightsHydroAlertHandler(publisher, as)

	repositories := repository.NewService(db)
	indexer := indexer.NewService(as, repositories, &skipRepoSyncAPI{rs: repositories}, es, insightsHandler)

	jobs := aqueduct.DefaultInProcessJob(indexer)
	links := alertlinks.NewService(alertlink.NewService(db), NullLinkHydroPublisher{}, es)

	mockCtrl := gomock.NewController(t)
	codeQLRunPublisher := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	guidMap := make(map[string]string)

	return &testEnv{
		ctx:             ctx,
		db:              db,
		es:              es,
		t:               t,
		publisher:       publisher,
		as:              as,
		prAlertsService: pr_alerts.NewService(db),
		analyses:        mysqlanalysis.NewService(db),
		ds:              delivery.NewService(db),
		gc:              gc.NewService(db, nil, 1), // Set batch size to 1 to test batching
		tss:             timeline.NewService(db),
		archiveService:  archiveService,
		tools:           toolService,
		configurations:  configuration.NewService(db),
		rs:              rule.NewService(db),
		repos:           repositories,
		ss:              sarifStore,
		managedAnalysis: managedanalysis.NewService(db, codeQLRunPublisher),
		ams:             analysismessage.NewService(db),
		insightsHandler: insightsHandler,
		jobs:            jobs,
		al:              links,
		paGuids:         guidMap,
	}
}

// alert captures the essence of an alert for matching.
// The filePath is used to create stable ID (and will be used as a proxy for that)
// The paKey is used to distinguish between
// physical alerts via their generated GUIDs
type testAlertT struct {
	filePath string
	paKey    string
	guid     string // will be generated at delivery time

	// If non-zero, these are used to generate location information of the
	// corresponding types.
	resultLine   int
	relatedPath  string
	relatedLine  int
	codeFlowPath string
	codeFlowLine int
}

func testAlert(filePath, paKey string) testAlertT {
	return testAlertT{
		filePath: filePath,
		paKey:    paKey,
	}
}

// deliverAlerts creates a dummy sarif with the specified alerts and pushes it
// for the specified ref. The single created analysis is returned.
func (e *testEnv) deliverAlerts(cfg testConfig, a ...testAlertT) *ts.Analysis {
	// generate unique guids for each alert
	for i := range a {
		guid := uuid.NewString()
		a[i].guid = guid
		e.paGuids[a[i].paKey] = guid
	}

	sarif := testSarif(cfg, a)

	bytes, err := json.Marshal(sarif)
	require.NoError(e.t, err)

	analysis := e.deliverAndStoreSARIF(cfg, "", bytes)
	return analysis
}

type testSarifService struct {
	data []byte
}

func (s *testSarifService) Download(_ context.Context, _ string) (*bytes.Buffer, error) {
	buf := &bytes.Buffer{}
	_, err := io.Copy(buf, bytes.NewReader(s.data))
	return buf, err
}
func (s *testSarifService) Upload(_ context.Context, _ io.Reader, _ string) error {
	return nil
}
func (s *testSarifService) Archive(_ context.Context, _ io.Reader, path string) (string, error) {
	return path, nil
}

func (s *testSarifService) Open(_ context.Context) error {
	return nil
}

func (s *testSarifService) Close(_ context.Context) error {
	return nil
}

func (s *testSarifService) Check(_ context.Context) error {
	return nil
}

func (e *testEnv) deliverSARIFMultiple(cfg testConfig, sarifPath string) []*ts.Analysis {
	data, err := os.ReadFile(sarifPath)
	require.NoError(e.t, err)
	return e.processSARIF(cfg, data, sarifPath)
}

func (e *testEnv) deliverSARIF(cfg testConfig, sarifPath string) *ts.Analysis {
	analyses := e.deliverSARIFMultiple(cfg, sarifPath)
	require.Len(e.t, analyses, 1)
	return analyses[0]
}

// deliverAndStoreSARIF is a version of deliverSARIF that uses the same SARIF store for the
// processor and archiver.
func (e *testEnv) deliverAndStoreSARIF(cfg testConfig, sarifPath string, sarifContent []byte) *ts.Analysis {
	if sarifPath != "" && sarifContent == nil {
		data, err := os.ReadFile(sarifPath)
		require.NoError(e.t, err)
		sarifContent = data
	}
	if sarifPath == "" {
		sarifPath = "test.sarif"
	}

	err := e.ss.Upload(e.ctx, bytes.NewReader(sarifContent), sarifPath)
	require.NoError(e.t, err)
	info := e.newDelivery(cfg, sarifPath)

	// Define explicit limit
	ls := cfg.limitSelector
	// If no explicit limit is set then define small limits for a specific repo for testing
	if ls == nil {
		small := limits.LimitsDefault()
		small.ResPerRunLimit = 1000
		small.RulesPerRunLimit = 1000
		ls = limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{999: small}, false)
	}

	var as AnalysisCreator
	switch cfg.commitBehavior {
	case CommitBehaviorNormal:
		as = e.analyses
	case CommitBehaviorNone:
		as = AnalysisServiceNoCommit{e.analyses}
	case CommitBehaviorFail:
		as = AnalysisServiceFail{e.analyses}
	case CommitBehaviorNoPromote:
		as = AnalysisServiceNoPromote{e.analyses}
	}
	p := New(e.as, as, e.ds, e.ams, e.ss, e.ss, e.tools, e.configurations, e.rs, e.tss, e.repos, nil, ls, &tssarif.NullRuleMetadataAugmentor{}, e.managedAnalysis, nil, e.jobs)

	analyses, err := p.ProcessNewDelivery(e.ctx, info)
	require.NoError(e.t, err)
	require.Len(e.t, analyses, 1)
	return analyses[0]
}

// processSARIF delivers the sarif file at the given path (relative to the
// invoking test).
func (e *testEnv) processSARIF(cfg testConfig, sarif []byte, path string) []*ts.Analysis {
	info := e.newDelivery(cfg, path)

	// Define explicit limit
	ls := cfg.limitSelector
	// If no explicit limit is set then define small limits for a specific repo for testing
	if ls == nil {
		small := limits.LimitsDefault()
		small.ResPerRunLimit = 1000
		small.RulesPerRunLimit = 1000
		ls = limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{999: small}, false)
	}

	var as AnalysisCreator
	switch cfg.commitBehavior {
	case CommitBehaviorNormal:
		as = e.analyses
	case CommitBehaviorNone:
		as = AnalysisServiceNoCommit{e.analyses}
	case CommitBehaviorFail:
		as = AnalysisServiceFail{e.analyses}
	case CommitBehaviorNoPromote:
		as = AnalysisServiceNoPromote{e.analyses}
	}
	p := New(e.as, as, e.ds, e.ams, &testSarifService{sarif}, &testSarifService{sarif}, e.tools, e.configurations, e.rs, e.tss, e.repos, nil, ls, &tssarif.NullRuleMetadataAugmentor{}, e.managedAnalysis, nil, e.jobs)

	analyses, err := p.ProcessNewDelivery(e.ctx, info)
	require.NoError(e.t, err)

	return analyses
}

// AnalysisServiceNoCommit is a mock implementation of the AnalysisCreator interface.
// It stubs out CommitAnalysis only, to prevent that from being called.
type AnalysisServiceNoCommit struct {
	*mysqlanalysis.Service
}

func (a AnalysisServiceNoCommit) CommitAnalysis(ctx context.Context, analysis *ts.Analysis) error {
	// Prevent the analysis from being committed.
	return nil
}

// AnalysisServiceFail is a mock implementation of the AnalysisCreator interface.
// It ensures that CommitAnalysis marks the analysis as failed.
type AnalysisServiceFail struct {
	*mysqlanalysis.Service
}

func (a AnalysisServiceFail) CommitAnalysis(ctx context.Context, analysis *ts.Analysis) error {
	analysis.Failed = true
	analysis.MostRecent = false
	return a.Service.CommitAnalysis(ctx, analysis)
}

// AnalysisServiceNoPromote is a mock implementation of the AnalysisCreator interface.
// It ensures that CommitAnalysis does not set most recent to true.
type AnalysisServiceNoPromote struct {
	*mysqlanalysis.Service
}

func (a AnalysisServiceNoPromote) CommitAnalysis(ctx context.Context, analysis *ts.Analysis) error {
	analysis.MostRecent = false
	return a.Service.CommitAnalysis(ctx, analysis)
}

// finalize finishes the specified analysis, effectively committing it
func (e *testEnv) finalize(analysis *ts.Analysis, baseline *ts.Analysis) {
	// As we did a partialDelivery, the baseline might be incorrectly set.
	if baseline != nil {
		analysis.BaselineID = &baseline.ID
	}
	analysis.MostRecent = true
	err := e.analyses.CommitAnalysis(e.ctx, analysis)
	require.NoError(e.t, err)
}

// newDelivery creates a ts.Delivery from the given testConfig
func (e *testEnv) newDelivery(cfg testConfig, sarif string) *ts.Delivery {
	commit := cfg.commitOid
	if commit == "" {
		commit = e.newCommit()
	}
	ref := cfg.ref
	if ref == "" {
		ref = "main"
	}
	analysisKey := cfg.analysisKey
	if analysisKey == "" {
		analysisKey = "analysis"
	}

	startTime := cfg.startTime
	if startTime == nil {
		stTime := time.Date(2019, time.March, 10, 0, 0, 0, 0, time.UTC)
		startTime = &stTime
	}

	repositoryID := cfg.repositoryID
	if repositoryID == 0 {
		repositoryID = testRepoID
	}

	sourceRepositoryID := cfg.sourceRepositoryID
	if sourceRepositoryID == 0 {
		sourceRepositoryID = repositoryID
	}

	env := cfg.environment
	if env == nil {
		env = ts.AnalysisEnv{}
	}

	return &ts.Delivery{
		RepositoryID:       repositoryID,
		CommitOid:          commit,
		Ref:                []byte(ref),
		AnalysisKey:        ts.ToAnalysisKey(analysisKey),
		Environment:        env,
		BuildStartedAt:     startTime,
		SourceRepositoryID: sourceRepositoryID,
		SarifPath:          sarif,
	}
}

// requireOpen checks that the alerts returned from the `Alerts` call (for open alerts) matches the expected alerts.
func (e *testEnv) requireOpen(refs []string, expected ...testAlertT) {
	refBytes := transforms.Map(refs, func(s string) []byte {
		return []byte(s)
	})

	filter := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: testRepoID,
		Refs:         refBytes,
		State:        ts.AnalysisStateFilterMostRecent,
	}
	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 10000},
		Preloads: []string{
			"Rule",
			"Rule.Tags",
			"Rule.Tool",
			"PhysicalAlerts",
			"PhysicalAlerts.Analysis",
			"PhysicalAlerts.Analysis.Tool",
			"PhysicalAlerts.Analysis.ToolVersion",
			"PhysicalAlerts.LastSeenAnalysis",
		},
		SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
	}

	actual, err := e.as.Alerts(e.ctx, testRepoID, filter, analysisFilter, options)
	require.NoError(e.t, err)

	e.requireAlerts(refs, expected, actual)

	// Validate counts
	counts, err := e.as.Count(e.ctx, testRepoID, filter, analysisFilter)
	require.True(e.t, err == nil)
	require.Equal(e.t, counts, uint64(len(actual)))
}

// requireRslv checks that the alerts returned from the `Alerts` call (for resolved alerts) matches the expected alerts.
func (e *testEnv) requireRslv(refs []string, expected ...testAlertT) {
	refBytes := transforms.Map(refs, func(s string) []byte {
		return []byte(s)
	})
	filter := ts.AlertFilter{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: testRepoID,
		Refs:         refBytes,
		State:        ts.AnalysisStateFilterMostRecent,
	}
	options := &ts.FindOptions{
		Pagination: &ts.Pagination{Limit: 10000},
		Preloads: []string{
			"Rule",
			"Rule.Tags",
			"Rule.Tool",
			"PhysicalAlerts",
			"PhysicalAlerts.Analysis",
			"PhysicalAlerts.Analysis.Tool",
			"PhysicalAlerts.Analysis.ToolVersion",
			"PhysicalAlerts.LastSeenAnalysis",
		},
		SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
	}

	actual, err := e.as.Alerts(e.ctx, testRepoID, filter, analysisFilter, options)
	require.NoError(e.t, err)

	e.requireAlerts(refs, expected, actual)

	// Validate counts
	counts, err := e.as.Count(e.ctx, testRepoID, filter, analysisFilter)
	require.True(e.t, err == nil)
	require.Equal(e.t, counts, uint64(len(actual)))
}

func (e *testEnv) toolIDs(names ...string) []ts.ToolID {
	var toolIDs []ts.ToolID

	query := e.db.Model(&ts.Tool{})

	if len(names) > 0 {
		query = query.Where("canonical_name IN (?)", names)
	}

	require.NoError(e.t, query.Pluck("id", &toolIDs).Error)
	return toolIDs
}

// requireAlerts checks that the actual alerts match the expected alerts
func (e *testEnv) requireAlerts(refs []string, expected []testAlertT, actual []*ts.LogicalAlert) {
	refm := map[string]bool{}
	for _, r := range refs {
		refm[r] = true
	}
	require.Equal(e.t, len(expected), len(actual), "different number of alerts")
	for i, la := range actual {
		canonical, err := la.Canonical()
		require.NoError(e.t, err)
		require.True(e.t, canonical.Analysis.MostRecent, "alert %v - has canonical physical alert not part of a most_recent analysis", la.FilePath)
		ex := expected[i]
		exGUID := e.paGuids[ex.paKey]
		require.Equal(e.t, la.Rule.SarifIdentifier, la.SarifIdentifier)
		require.Equal(e.t, ex.filePath, la.FilePath, "expected alert does not match")
		require.Equal(e.t, exGUID, *canonical.GUID, "alert %v does not have the right physical alert", la.FilePath)
		for _, pa := range la.PhysicalAlerts {
			if refs != nil {
				// We only allow physical alerts from the specified refs
				require.True(e.t, refm[string(pa.Analysis.Ref)], "refs %v - physical alert %v (in ref %v) should not be included", refs, pa.Message, pa.Analysis.Ref)
			}
			// We only allow physical alerts from analyses that are most recent
			require.True(e.t, pa.Analysis.MostRecent, "refs %v - physical alert %v should not be included (not most recent) - analysis: %v", refs, pa.Message, pa.Analysis.Ref, pa.Analysis.ID)
		}

		analysis := canonical.Analysis
		if canonical.IsFixed {
			analysis = canonical.LastSeenAnalysis
		}
		codeflows, err := e.archiveService.ExtractCodeFlows(e.ctx, analysis, []*ts.LogicalAlert{la})
		require.NoError(e.t, err)
		doc := codeflows[la.ID]
		for _, c := range doc.Document {
			require.Equal(e.t, ex.filePath, c.FilePath, "expected alert does not match for threadflow")
			require.Equal(e.t, "message for "+exGUID, *c.Message, "expected alert does not match for threadflow")
		}

		require.NoError(e.t, e.db.Find(&canonical.RelatedLocations, "physical_alert_id = ?", canonical.ID).Error)
		require.NotEmpty(e.t, canonical.RelatedLocations)

		for _, r := range canonical.RelatedLocations {
			require.Equal(e.t, ex.filePath, r.FilePath, "expected alert does not match for related location")
			require.Equal(e.t, "message for "+exGUID, r.Message, "expected alert does not match for related location")
		}

		// We check that the `PhysicalAlerts` endpoint also returns the most recent physical alerts
		physicalAlerts, err := e.as.PhysicalAlerts(e.ctx, la.RepositoryID, ts.AlertFilter{IDs: []ts.LogicalAlertID{la.ID}}, ts.AnalysisFilter{RepositoryID: la.RepositoryID, State: ts.AnalysisStateFilterMostRecent}, &ts.FindOptions{
			Preloads: []string{"Analysis"},
		})
		require.NoError(e.t, err)
		require.NotEmpty(e.t, physicalAlerts)
		require.Equal(e.t, la.ID, physicalAlerts[0].LogicalAlertID)
		for _, pa := range physicalAlerts {
			// We only allow physical alerts from analyses that are most recent
			require.True(e.t, pa.Analysis.MostRecent, "alert %v - physical alert (from `Alert`) %v should not be included (not most recent) - analysis: %v", pa.FilePath, pa.Message, pa.Analysis.ID)
		}

	}
}

// require that two lists of logical alerts are equivalent
func (e *testEnv) requireLogicalAlerts(expectedAlerts []*ts.LogicalAlert, actualAlerts []*ts.LogicalAlert) {
	require.Equal(e.t, len(expectedAlerts), len(actualAlerts), "different number of alerts")

	for i, expectedLA := range expectedAlerts {
		actualLA := actualAlerts[i]

		expected, err := expectedLA.Canonical()
		require.NoError(e.t, err)
		actual, err := actualLA.Canonical()
		require.NoError(e.t, err)

		require.Equal(e.t, expected.FilePath, actual.FilePath, "filepath %v and %v do not match", expected.FilePath, actual.FilePath)
		require.Equal(e.t, expected.Message, actual.Message, "message %v and %v do not match", expected.Message, actual.Message)

		require.Equal(e.t, len(expectedLA.PhysicalAlerts), len(actualLA.PhysicalAlerts), "different number of physical alerts for expected %v and actual %v", expected.Message, actual.Message)
	}
	// TODO loosely based on some of requireAlerts, but not sure how much deeper to go given current usage?
}

// requireToolByName creates or fetches a tool by name for testing
func requireToolByName(tb testing.TB, tools *tool.Service, repoID ts.RepositoryEID, toolName ts.ToolName) *ts.Tool {
	tb.Helper()

	tv := &ts.ToolVersion{
		Name: toolName,
		Tool: ts.ToolFromCanonicalName(toolName),
	}

	err := tools.FindOrCreate(context.Background(), []*ts.ToolVersion{tv})
	require.NoError(tb, err)
	require.NotZero(tb, tv.ID)
	require.NotZero(tb, tv.Tool.ID)
	return tv.Tool
}

func (e *testEnv) requireToolByName(repoID ts.RepositoryEID, name ts.ToolName) *ts.Tool {
	return requireToolByName(e.t, e.tools, repoID, name)
}

// requirePhysicalAlerts asserts that the number of physical alerts are as expected
func (e *testEnv) requirePhysicalAlertsForAnalysis(id ts.AnalysisID, expected int) {
	dbtest.RequireCount(e.t, expected, e.db.Model(ts.PhysicalAlert{}).Where("analysis_id = ?", id))
}

// performGC runs garbage collection on all analyses that are not most recent.
func (e *testEnv) performGC(kind ts.CleaningType) {
	// -1 is used as a limit to prevent timing issues with identical dates in tests.
	analyses, err := e.gc.FetchGarbageCollectableAnalyses(e.ctx, -1, 10000, 0)
	require.NoError(e.t, err)
	for _, a := range analyses {
		err = e.gc.HardDeleteFixedAlerts(e.ctx, a)
		require.NoError(e.t, err)
		err = e.gc.UpdateGarbageCollectionStatus(e.ctx, a)
		require.NoError(e.t, err)
	}
}

// newCommit returns a fresh commit for testing
func (e *testEnv) newCommit() ts.Sha {
	e.commitCounter += 1
	commitID := e.commitCounter
	return ts.ToSha("commit-" + strconv.Itoa(commitID))
}

// indexRepository fully indexes a repository in Elasticsearch with a step size of 1
func (e *testEnv) indexRepository(ctx context.Context, repo *ts.Repository) error {

	loader := e.as.NewLoader(repo)
	loader.SetBatchSize(1)
	return loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		docs, err := ts.SearchDocumentsFromAlerts(repo, alerts)
		if err != nil {
			return err
		}
		return e.es.IndexDocuments(ctx, ts.Index_OrgLevel, docs)
	})
}

// testSarif creates a dummy sarif with the specified alerts
func testSarif(cfg testConfig, alerts []testAlertT) *v2_1_0.SARIF {

	// NB we use alert.message as both ruleID and rule tag
	var rules []*v2_1_0.ReportingDescriptor
	for _, alert := range alerts {
		rules = append(rules, &v2_1_0.ReportingDescriptor{
			Id: alert.filePath,
			Properties: &v2_1_0.ReportingDescriptorPropertyBag{
				Tags: []string{alert.filePath},
			},
		})
	}

	return &v2_1_0.SARIF{
		Runs: []*v2_1_0.Run{
			{
				Tool: &v2_1_0.Tool{
					Driver: &v2_1_0.ToolComponent{
						Name:            cfg.tool.String(),
						SemanticVersion: cfg.toolVersion,
						Rules:           rules,
					},
				},
				Results: testSarifResults(alerts),
			},
		},
	}
}

// testSarifResults creates dummy sarif results for the specified alerts
func testSarifResults(alerts []testAlertT) (result []*v2_1_0.Result) {
	for _, a := range alerts {
		relatedFilePath := a.filePath
		if a.relatedPath != "" {
			relatedFilePath = a.relatedPath
		}

		codeFlowPath := a.filePath
		if a.codeFlowPath != "" {
			codeFlowPath = a.codeFlowPath
		}

		r := &v2_1_0.Result{
			Guid:   a.guid,
			RuleId: a.filePath,
			Locations: []*v2_1_0.Location{
				{
					PhysicalLocation: testSarifLocation(a.filePath, a.resultLine),
				},
			},
			CodeFlows: []*v2_1_0.CodeFlow{
				{
					ThreadFlows: []*v2_1_0.ThreadFlow{
						{
							Locations: []*v2_1_0.ThreadFlowLocation{
								{
									Location: &v2_1_0.Location{
										PhysicalLocation: testSarifLocation(codeFlowPath, a.codeFlowLine),
										Message:          &v2_1_0.Message{Text: "message for " + a.guid},
									},
								},
							},
						},
					},
				},
			},
			RelatedLocations: []*v2_1_0.Location{
				{
					PhysicalLocation: testSarifLocation(relatedFilePath, a.relatedLine),
					Message:          &v2_1_0.Message{Text: "message for " + a.guid},
				},
			},
			Message: &v2_1_0.Message{
				Text: "test message",
			},
		}
		result = append(result, r)
	}
	return
}

// testSarifLocation creates dummy sarif location for the specified alert
func testSarifLocation(path string, line int) *v2_1_0.PhysicalLocation {
	if line == 0 {
		line = 1
	}

	return &v2_1_0.PhysicalLocation{
		ArtifactLocation: &v2_1_0.ArtifactLocation{
			Uri: path,
		},
		Region: &v2_1_0.Region{
			StartLine: line,
		},
	}
}

type badAnalysisService struct {
	*mysqlanalysis.Service
}

func (bas *badAnalysisService) CreateAnalysis(_ context.Context, _ *ts.Analysis, _ ...ts.ToolID) error {
	return errors.New("failed to create analysis")
}

func TestCannotCreateAnalysis(t *testing.T) {
	db := dbtest.RequireConnection(t)
	env := requireTestEnv(t, db)

	d := &ts.Delivery{
		CommitOid:          "abcd",
		Ref:                []byte("ref"),
		RepositoryID:       ts.RepositoryEID(1234),
		SourceRepositoryID: ts.RepositoryEID(1234),
		RepositoryNWO:      "dsp-testing/test-repo",
		AnalysisName:       "workflow/job",
		Environment:        make(map[string]string),
		CheckoutURI:        "file:///tmp",
	}

	bas := &badAnalysisService{Service: env.analyses}

	data, err := os.ReadFile("../sarif/testdata/ruby-example.sarif")
	require.NoError(t, err)

	ss := &testSarifService{data: data}

	ls := limits.NewLimitSelector(nil, false)
	processor := New(env.as, bas, env.ds, env.ams, ss, nil, env.tools, env.configurations, env.rs, env.tss, env.repos, nil, ls, &tssarif.NullRuleMetadataAugmentor{}, env.managedAnalysis, nil, env.jobs)
	_, err = processor.ProcessNewDelivery(env.ctx, d)
	require.Error(t, err)
}

// CollectingPublisher implements the hydro publisher interface by just collecting all the
// events in an internal slice for later inspection.
type CollectingPublisher struct {
	newAnalyses        []*hydro_schemas_code_scanning_v0.Analysis
	processedAnalayses []*hydro_schemas_code_scanning_v0.Analysis
	failedAnalyses     []*hydro_schemas_code_scanning_v0.Analysis
	alertEvents        []*hydro_schemas_turboscan_v0.AlertEvent
	insightBatches     []*hydro_schemas_github_security_center_v0.InsightsEntityBatch
}

func (c *CollectingPublisher) NewAnalysis(ctx context.Context, analysis *hydro_schemas_code_scanning_v0.Analysis) error {
	c.newAnalyses = append(c.newAnalyses, analysis)
	return nil
}

func (c *CollectingPublisher) ProcessedAnalysis(ctx context.Context, analysis *hydro_schemas_code_scanning_v0.Analysis) error {
	c.processedAnalayses = append(c.processedAnalayses, analysis)
	return nil
}

func (c *CollectingPublisher) FailedAnalysis(ctx context.Context, analysis *hydro_schemas_code_scanning_v0.Analysis) error {
	c.failedAnalyses = append(c.failedAnalyses, analysis)
	return nil
}

func (c *CollectingPublisher) AlertEvent(ctx context.Context, alert *hydro_schemas_turboscan_v0.AlertEvent) error {
	c.alertEvents = append(c.alertEvents, alert)
	return nil
}

func (c *CollectingPublisher) InsightsEntityBatchEvent(ctx context.Context, batch *hydro_schemas_github_security_center_v0.InsightsEntityBatch) error {
	c.insightBatches = append(c.insightBatches, batch)
	return nil
}

type NullLinkHydroPublisher struct{}

func (n NullLinkHydroPublisher) AlertLinksCreateBatch(context.Context, []*hydro_schemas_code_scanning_v0.AlertLinkCreate) error {
	return nil
}

func (n NullLinkHydroPublisher) AlertLinksUpdateBatch(context.Context, []*hydro_schemas_code_scanning_v0.AlertLinkUpdate) error {
	return nil
}
