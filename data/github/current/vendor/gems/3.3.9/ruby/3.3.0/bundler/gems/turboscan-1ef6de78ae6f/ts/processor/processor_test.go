package processor_test

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/github/turboscan/ts/auditlog"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/indexer"
	"github.com/github/turboscan/ts/processor"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"golang.org/x/exp/maps"

	"github.com/github/turboscan/ts/twirp"

	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"

	"github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/configuration"

	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"go.uber.org/mock/gomock"

	"github.com/jinzhu/gorm"

	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/dbtest"

	"github.com/stretchr/testify/suite"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/limits"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/store"
)

type ProcessorTestSuite struct {
	suite.Suite
	ctx context.Context

	db                      *gorm.DB
	alerts                  *alert.Service
	analyses                *analysis.Service
	archiveService          *archiver.Service
	ams                     *analysismessage.Service
	ds                      *delivery.Service
	sarifs                  store.SarifStore
	timelines               *timeline.Service
	tools                   *tool.Service
	configurations          *configuration.Service
	rules                   *rule.Service
	repos                   *repository.Service
	alertEventHandler       *mockAlertEventHandler
	mockMAEnablementChecker *mockMAEnablementChecker
	jobs                    aqueduct.InProcessJob
	ls                      *limits.LimitSelector
	rma                     tssarif.RuleMetadataAugmentor

	processor     *processor.Processor
	sampleSarifID ts.SarifID
}

func (s *ProcessorTestSuite) defaultDelivery(sarifPath string) *ts.Delivery {
	return &ts.Delivery{
		CommitOid:          "abcd",
		Ref:                []byte("ref"),
		RepositoryID:       ts.RepositoryEID(1234),
		SourceRepositoryID: ts.RepositoryEID(1234),
		RepositoryNWO:      "dsp-testing/test-repo",
		AnalysisName:       "workflow/job",
		Environment:        make(map[string]string),
		CheckoutURI:        "file:///tmp",
		SarifID:            s.sampleSarifID,
		SarifPath:          sarifPath,
		TrackStatus:        true,
	}
}

// SetupTest runs before each test
func (s *ProcessorTestSuite) SetupTest() {
	var err error
	s.ctx = context.Background()

	s.sampleSarifID = "b4774e3d-9486-4589-b59e-9086dab3c799"
	s.db = dbtest.RequireConnection(s.T())

	s.alerts = alert.TestService(s.db)
	s.ams = analysismessage.NewService(s.db)
	s.tools = tool.NewService(s.db, limits.TestLimitSelector())
	s.configurations = configuration.NewService(s.db)
	s.analyses = analysis.NewService(s.db)
	s.ds = delivery.NewService(s.db)
	s.sarifs = store.NewSarifStore(config.STORAGE_MEMORY, &config.Config{MaxSarifSize: 0})
	err = s.sarifs.Open(s.ctx)
	s.NoError(err)
	s.archiveService = archiver.NewService(s.db, s.sarifs)

	s.timelines = timeline.NewService(s.db)
	s.rules = rule.NewService(s.db)

	allowNoRules, limitOnlyTags, limitOnlyExtensions, limitOnlySteps, limitOnlyRelatedLocations := limits.LimitsDefault(), limits.LimitsDefault(), limits.LimitsDefault(), limits.LimitsDefault(), limits.LimitsDefault()
	allowNoRules.RulesPerRunLimit = 0
	limitOnlyTags.TagsPerRuleLimit = 4
	limitOnlyExtensions.ToolExtensionsPerRunLimit = 2
	limitOnlySteps.StepsPerResLimit = 2
	limitOnlyRelatedLocations.LocPerResLimit = 1
	allowOneResult := limits.LimitsDefault()
	allowOneResult.ResPerRunLimit = 1
	s.ls = limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{
		999: {RunsPerSarifLimit: 0},
		998: allowNoRules,
		997: limitOnlyExtensions,
		996: allowOneResult,
		995: limitOnlyTags,
		994: limitOnlySteps,
		993: limitOnlyRelatedLocations,
		992: limits.LimitsDefault().WithFixesCopiedLimit(2),
	}, false)

	s.rma, err = tssarif.DefaultRuleMetadataAugmentor()
	s.NoError(err)
	s.repos = repository.NewService(s.db)
	es := elasticsearch.SetUpTestElasticSearchService(s.T())
	s.alertEventHandler = &mockAlertEventHandler{}

	indexer := indexer.NewService(s.alerts, s.repos, nil, es, &publishers.NullHandler{})

	s.jobs = aqueduct.DefaultInProcessJob(indexer)
	s.mockMAEnablementChecker = &mockMAEnablementChecker{}

	s.processor = processor.New(s.alerts, s.analyses, s.ds, s.ams, s.sarifs, s.sarifs, s.tools, s.configurations, s.rules, s.timelines, s.repos, nil, s.ls, s.rma, s.mockMAEnablementChecker, s.alertEventHandler, s.jobs)
}

func (s *ProcessorTestSuite) TearDownSuite() {
	s.sarifs.Close(s.ctx)
}

func (s *ProcessorTestSuite) uploadFixtureFile(path string) string {
	f, err := os.Open(path)
	s.NoError(err)
	defer f.Close()
	sp := "testing/" + uuid.NewString()
	err = s.sarifs.Upload(s.ctx, f, sp)
	s.NoError(err)
	return sp
}

// mockMAEnablementChecker is a mock implementation of the ActiveConfigChecker interface
type mockMAEnablementChecker struct {
	active bool
}

func (c *mockMAEnablementChecker) IsEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, error) {
	return c.active, nil
}

var _ processor.MAEnablementChecker = &mockMAEnablementChecker{}

func (s *ProcessorTestSuite) TestBadAnalysisName() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	d := s.defaultDelivery(sarifPath)
	d.AnalysisName = `👾 CodeQL`

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)

	dbtest.RequireCount(s.T(), 1, s.db.Model(&ts.Analysis{}))
}

func (s *ProcessorTestSuite) TestLongSarifId() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/id-overflow.sarif")

	d := s.defaultDelivery(sarifPath)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "sarif identifier exceeds maximum length of 255 characters")
}

func (s *ProcessorTestSuite) TestArtifactLocationNormalisingUsingID() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example_with_artifact_location_id.sarif")

	d := s.defaultDelivery(sarifPath)

	// test that the data is correctly mapped
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.NotEmpty(analyses)
	s.Equal(analyses[0].PhysicalAlerts[0].LogicalAlert.FilePath, "main.js")
	s.Equal(analyses[0].PhysicalAlerts[1].LogicalAlert.FilePath, "src/promiseUtils.js")
	s.Equal(analyses[0].PhysicalAlerts[1].RelatedLocations[0].FilePath, "src/ParseObject.js")
	s.Equal(analyses[0].PhysicalAlerts[1].RelatedLocations[1].FilePath, "src/LiveQueryClient.js")

	// test to ensure the data is correctly saved
	as := []*ts.Analysis{}
	s.NoError(s.db.Preload("PhysicalAlerts.LogicalAlert").Preload("PhysicalAlerts.RelatedLocations").Find(&as).Error)
	s.Len(as, 1)
	s.False(as[0].Failed)
	s.Equal(as[0].PhysicalAlerts[0].LogicalAlert.FilePath, "main.js")
	s.Equal(as[0].PhysicalAlerts[1].LogicalAlert.FilePath, "src/promiseUtils.js")
	s.Equal(as[0].PhysicalAlerts[1].RelatedLocations[0].FilePath, "src/ParseObject.js")
	s.Equal(as[0].PhysicalAlerts[1].RelatedLocations[1].FilePath, "src/LiveQueryClient.js")
}

func (s *ProcessorTestSuite) TestArtifactLocationNormalisingUsingIDWithoutIndex() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example_with_artifact_location_id_without_index.sarif")

	d := s.defaultDelivery(sarifPath)

	// test that the data is correctly mapped
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.NotEmpty(analyses)
	s.Equal(analyses[0].PhysicalAlerts[0].LogicalAlert.FilePath, "main.js")
	s.Equal(analyses[0].PhysicalAlerts[1].LogicalAlert.FilePath, "src/promiseUtils.js")
	s.Equal(analyses[0].PhysicalAlerts[1].RelatedLocations[0].FilePath, "src/ParseObject.js")
	s.Equal(analyses[0].PhysicalAlerts[1].RelatedLocations[1].FilePath, "src/LiveQueryClient.js")

	// test to ensure the data is correctly saved
	as := []*ts.Analysis{}
	s.NoError(s.db.Preload("PhysicalAlerts.LogicalAlert").Preload("PhysicalAlerts.RelatedLocations").Find(&as).Error)
	s.Len(as, 1)
	s.False(as[0].Failed)
	s.Equal(as[0].PhysicalAlerts[0].LogicalAlert.FilePath, "main.js")
	s.Equal(as[0].PhysicalAlerts[1].LogicalAlert.FilePath, "src/promiseUtils.js")
	s.Equal(as[0].PhysicalAlerts[1].RelatedLocations[0].FilePath, "src/ParseObject.js")
	s.Equal(as[0].PhysicalAlerts[1].RelatedLocations[1].FilePath, "src/LiveQueryClient.js")
}

func (s *ProcessorTestSuite) TestProcessNewBuild() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)

	dbtest.RequireCount(s.T(), 1, s.db.Model(&ts.Analysis{}))
}

func (s *ProcessorTestSuite) TestProcessNewBuild_AugmentsErrorWhenRulesBad() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/invalid_rule.sarif")

	_, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "could not convert rule")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnrecoverableAnalysis, pe.ErrorType)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_NoRules() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/no_rules.sarif")
	d := s.defaultDelivery(sarifPath)
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Equal(uint(1), analyses[0].RulesCount)
	s.NotNil(analyses[0].ProcessWarning)
}

func (s *ProcessorTestSuite) TestProcess_EmptySarif() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/empty.json")
	d := s.defaultDelivery(sarifPath)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	analysisMessages := []*ts.AnalysisMessage{}
	s.NoError(s.db.Find(&analysisMessages).Error)
	// the delivery should have an associated AnalysisMessage warning that there are no runs
	s.Len(analysisMessages, 1)
	s.Equal(ts.MessageSarifNoRuns, analysisMessages[0].Key)
	// the delivery should have been failed
	dbtest.RequireCount(s.T(), 1, s.db.Model(ts.Delivery{}).Where("complete = 1 AND failed = 1"))

}

func (s *ProcessorTestSuite) TestProcessNewBuild_CodeQLConfig() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/codeql_config.sarif")
	d := s.defaultDelivery(sarifPath)
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Len(analyses[0].AnalysisQuerySuites, 3)
	s.NotNil(analyses[0].DefaultQueriesDisabled)
	s.True(*analyses[0].DefaultQueriesDisabled)
	s.Equal(analyses[0].AnalysisQuerySuites[0].Type, ts.AnalysisQuerySuiteTypeLocalQuery)
	s.Equal(analyses[0].AnalysisQuerySuites[1].Type, ts.AnalysisQuerySuiteTypeBuiltinSuite)
	s.Equal(analyses[0].AnalysisQuerySuites[2].Type, ts.AnalysisQuerySuiteTypeExternalRepo)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_WithProcessError() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/corrupt.sarif.gz")

	_, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "parsing restricted subset of SARIF data has failed")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnrecoverableDelivery, pe.ErrorType)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_WithUncompressError() {
	sp := "testing/foo.sarif.gz"
	d := s.defaultDelivery(sp)

	// Upload invalid gz data
	err := s.sarifs.Upload(s.ctx, bytes.NewReader([]byte{42}), sp)
	s.NoError(err)
	d.SarifPath = sp

	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "failed decompressing file")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnrecoverableDelivery, pe.ErrorType)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_WithParsingSarifError() {
	sp := "testing/foo.sarif"
	d := s.defaultDelivery(sp)

	// Upload invalid data
	err := s.sarifs.Upload(s.ctx, bytes.NewReader([]byte{42}), sp)
	s.NoError(err)
	d.SarifPath = sp
	s.NoError(err)

	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "parsing restricted subset of SARIF data has failed")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnrecoverableDelivery, pe.ErrorType)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_WithOutOfOrderDelivery() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	d := s.defaultDelivery(sarifPath)

	t1 := time.Date(2018, time.February, 15, 0, 0, 0, 0, time.UTC)
	d.BuildStartedAt = &t1

	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
}

type mockAlertEventHandler struct {
	Events  []*ts.TimelineEvent
	Numbers []uint32
	Alerts  []*ts.LogicalAlert
}

func (m *mockAlertEventHandler) NewAlertEvent(_ context.Context, la *ts.LogicalAlert, event *ts.TimelineEvent, _ auditlog.AuditLogContext) error {
	m.Events = append(m.Events, event)
	m.Numbers = append(m.Numbers, la.Number)
	m.Alerts = append(m.Alerts, la)

	// verify every eligible alert can be marshalled
	for idx, la := range m.Alerts {
		if m.Events[idx].EventType != ts.TimelineEventTypeAlertDeletedByUser {
			_, err := twirp.GetMarshaledResult(*la)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

func (m *mockAlertEventHandler) Flush() error {
	return nil
}

func (m *mockAlertEventHandler) Reset(s *ProcessorTestSuite) {
	m.Events = nil
	m.Numbers = nil
	m.Alerts = nil
	s.NoError(m.Flush())
}

func newAnalysis(
	repositoryID ts.RepositoryEID,
	commitOid ts.Sha,
	ref string,
	analysisName ts.AnalysisName,
	category ts.Category,
	tool *ts.Tool,
	environment map[string]string,
	startTime *sqltime.Time,
) *ts.Analysis {
	return &ts.Analysis{
		RepositoryID:       repositoryID,
		SourceRepositoryID: repositoryID,
		Ref:                []byte(ref),
		CommitOid:          commitOid,
		AnalysisName:       analysisName,
		Category:           category,
		ToolID:             tool.ID,
		Tool:               tool,
		Environment:        environment,
		MostRecent:         true,
		AnalysisComplete:   true,
		BuildStartedAt:     startTime,
	}
}

func (s *ProcessorTestSuite) TestProcessNewBuild_ProducingOutdatedEvent() {
	delivery := s.defaultDelivery("")
	codeQL := &ts.Tool{CanonicalName: "CodeQL", GUID: "aaa"}

	delivery.OutdatedConfiguration = ts.OutdatedConfiguration{ToolName: codeQL.CanonicalName, Category: "my-cat"}

	// create baseline analysis (which is required during the processing of an outdated delivery)
	dbtest.RequireCreate(s.T(), s.db, codeQL)

	// create test rule (used for serialization of result)
	testRule := &ts.Rule{Tool: codeQL, SarifIdentifier: "test"}
	dbtest.RequireCreate(s.T(), s.db, testRule)

	date := sqltime.Now()

	baselineAnalysis := newAnalysis(delivery.RepositoryID, delivery.CommitOid, string(delivery.Ref), delivery.AnalysisName, delivery.OutdatedConfiguration.Category, codeQL, map[string]string{}, &date)
	dbtest.RequireCreate(s.T(), s.db, baselineAnalysis)

	l := &ts.LogicalAlert{
		RepositoryID:          delivery.RepositoryID,
		Number:                uint32(1),
		StableAlertIdentifier: make([]byte, 8),
		RuleID:                testRule.ID,
	}
	dbtest.RequireCreate(s.T(), s.db, &l)

	now := sqltime.Now()
	p := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            baselineAnalysis.ID,
		RuleID:                l.RuleID,
		LastStateChangeAt:     now,
	}
	dbtest.RequireCreate(s.T(), s.db, &p)

	// act & assert
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Len(s.alertEventHandler.Events, 1)
	s.Equal(ts.TimelineEventTypeAlertClosedBecameOutdated, s.alertEventHandler.Events[0].EventType)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_ProducingEvents() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)

	s.Len(s.alertEventHandler.Events, 2)
	s.Len(s.alertEventHandler.Numbers, 2)
	s.Len(s.alertEventHandler.Alerts, 2)
	s.Equal(ts.TimelineEventTypeAlertCreated, s.alertEventHandler.Events[0].EventType)
	s.Equal(s.alertEventHandler.Events[0].LogicalAlertID, s.alertEventHandler.Alerts[0].ID)
	s.Len(s.alertEventHandler.Alerts[0].PhysicalAlerts, 1)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_ProducingSingleInstances() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	d := s.defaultDelivery(sarifPath)
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)

	s.Len(s.alertEventHandler.Events, 2)
	s.Len(s.alertEventHandler.Numbers, 2)
	s.Len(s.alertEventHandler.Alerts, 2)

	for _, event := range s.alertEventHandler.Events {
		s.False(event.NonUnique)
	}

	// Reset the AlertEventHandler to see the new results
	s.alertEventHandler.Alerts = nil
	s.alertEventHandler.Numbers = nil
	s.alertEventHandler.Events = nil
	s.NoError(s.alertEventHandler.Flush())

	// Process the same analysis again for a different ref.
	sarifPath = s.uploadFixtureFile("../sarif/testdata/empty.sarif")
	d = s.defaultDelivery(sarifPath)
	d.Ref = []byte("refs/heads/master")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")
	d = s.defaultDelivery(sarifPath)
	d.Ref = []byte("refs/heads/master")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Len(s.alertEventHandler.Events, 2)
	s.Len(s.alertEventHandler.Numbers, 2)
	s.Len(s.alertEventHandler.Alerts, 2)

	s.Equal(ts.TimelineEventTypeAlertAppearedInBranch, s.alertEventHandler.Events[0].EventType)
	s.Equal(s.alertEventHandler.Events[0].LogicalAlertID, s.alertEventHandler.Alerts[0].ID)
	s.Len(s.alertEventHandler.Alerts[0].PhysicalAlerts, 1)
	// The physical alert we return must be the one for the analysis we just uploaded.
	canonical, err := s.alertEventHandler.Alerts[0].Canonical()
	s.NoError(err)
	s.Equal(analyses[0].ID, canonical.AnalysisID)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_ReturnsAnalysisWithTool() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)
	s.NotNil(analyses[0].Tool)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_FailsOnExecutionSuccessfulFalseCodeQL() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/execution_failed_codeql.sarif")

	_, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "unsuccessful execution")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnsuccessfulAnalysis, pe.ErrorType)
	dbtest.RequireCount(s.T(), 0, s.db.Model(&ts.PhysicalAlert{}))
}

func (s *ProcessorTestSuite) TestProcessNewBuild_FailsOnExecutionSuccessfulFalse() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/execution_failed.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	var count int
	s.NoError(s.db.Model(ts.ProcessError{}).Count(&count).Error)
	s.Equal(0, count)
	s.NotEmpty(analyses)
	s.NotNil(analyses[0].ProcessWarning)
}

func (s *ProcessorTestSuite) TestProcessNewBuild_AcceptsInvalidInvocation() {
	// This sarif has no executionSuccessful property, so it defaults to true and continues successfully.
	sarifPath := s.uploadFixtureFile("../sarif/testdata/invalid_invocation.sarif")

	_, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	dbtest.RequireCount(s.T(), 1, s.db.Model(&ts.PhysicalAlert{}))
}

func (s *ProcessorTestSuite) Test_Limit() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	// Special repository value 999 has a RunsPerSarifLimit of 0.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 999

	a, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(a, 0)
}

func (s *ProcessorTestSuite) Test_SoftLimitResultsPerRun() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	// Special repository value 996 has a ResultsPerRun limit of 1.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 996

	a, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(a, 1)

	var analysisMessages []*ts.AnalysisMessage
	s.NoError(s.db.Find(&analysisMessages).Error)
	s.Len(analysisMessages, 1)
	s.Equal("sarif-soft-limit-results-per-run", string(analysisMessages[0].Key))
}

func (s *ProcessorTestSuite) Test_SoftLimitThreadFlows() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example-steps-soft-limits.sarif")

	// Special repository value 994 has a StepsPerRes limit of 2.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 994

	a, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(a, 1)

	var analysisMessages []*ts.AnalysisMessage
	s.NoError(s.db.Find(&analysisMessages).Error)
	s.Len(analysisMessages, 1)
	s.Equal("sarif-soft-limit-thread-flows", string(analysisMessages[0].Key))
}

func (s *ProcessorTestSuite) Test_SoftLimitRelatedLocations() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example-locations-per-result-soft-limits.sarif")

	// Special repository value 993 has a LocPerRes limit of 1.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 993

	a, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(a, 1)

	var analysisMessages []*ts.AnalysisMessage
	s.NoError(s.db.Find(&analysisMessages).Error)
	s.Len(analysisMessages, 1)
	s.Equal("sarif-soft-limit-related-locations", string(analysisMessages[0].Key))
}

func (s *ProcessorTestSuite) Test_RuleLimitIncludesExtensions() {
	// This file only has rules defined in its extensions, none at the driver level
	// but the rule limit should still be applied to it.
	sarifPath := s.uploadFixtureFile("../sarif/testdata/combineExtensions.sarif")

	// Special repository value 998 has a RulesPerRunLimit of 0
	// but all other restrictions are the same as the default.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 998

	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "more rules per run than allowed")
}

func (s *ProcessorTestSuite) Test_RuleTagsSoftLimitWarning() {
	// This file has 6 rule tags
	sarifPath := s.uploadFixtureFile("../sarif/testdata/multi_rule_tags.sarif")

	// Special repository with value 995 has a TagsPerRuleLimit set to 4 (with all other restrictions having the default value),
	// so that it's violated by the passed sarif.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 995

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)

	warnings := analyses[0].ProcessWarning
	s.Equal(*warnings, "Some tags for 2 rule(s) were ignored as they exceeded the limit of 4 tags. One such rule is 'py/other-kind-of-rule'.")

	var analysisMessages []*ts.AnalysisMessage
	s.NoError(s.db.Find(&analysisMessages).Error)
	s.Len(analysisMessages, 1)

	s.Equal(ts.MessageSarifSoftLimitTagsPerRule, analysisMessages[0].Key)
}

func (s *ProcessorTestSuite) Test_ToolExtensionLimit() {
	// This file has 3 tool extensions
	sarifPath := s.uploadFixtureFile("../sarif/testdata/multi_extensions.sarif")

	// Special repository value 997 has a ToolExtensionsPerRunLimit set to 2 so that it violated in the passed sarif file
	// but all other restrictions are the same as the default.
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = 997

	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "more tool extensions per run than allowed")
}

func (s *ProcessorTestSuite) TestFetchSarifRuns_NoTool() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example_no_tool.sarif")

	a, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(a, 0)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "missing a tool")
}

func (s *ProcessorTestSuite) TestFetchSarifRuns_Combine() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example_multi_tool.sarif")

	a, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(a, 2)
	s.Len(a[0].PhysicalAlerts, 1)
	s.Len(a[1].PhysicalAlerts, 1)
}

func (s *ProcessorTestSuite) TestFetchSarifRuns_ExtensionsCombined() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/rulesExtensions.sarif")

	d := s.defaultDelivery(sarifPath)
	a, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(a, 1)

	a0 := &ts.Analysis{ID: a[0].ID, RepositoryID: a[0].RepositoryID, ArchivalDataUrl: a[0].ArchivalDataUrl}
	err = s.archiveService.Unarchive(s.ctx, a0)
	s.NoError(err)

	// jq '.runs[].results | length' ts/sarif/testdata/rulesExtensions.sarif = 5, 5
	s.Len(a0.PhysicalAlerts, 10)

	// two in each driver
	s.Len(a0.Rules, 4)

	for _, pa := range a[0].PhysicalAlerts {
		rule, ok := a0.Rules[pa.RuleSarifIdentifier]
		s.True(ok)
		switch pa.RuleSarifIdentifier[strings.LastIndex(pa.RuleSarifIdentifier, "-")+1:] {
		case "1":
			s.Equal(fmt.Sprintf("%s shortDescription 1.0.0", rule.Name), rule.ShortDescription)
		case "2":
			s.Equal(fmt.Sprintf("%s shortDescription 1.0.1", rule.Name), rule.ShortDescription)
		default:
			s.Fail("expected SARIF identifier to end in -1 or -2")
		}
	}
}

func (s *ProcessorTestSuite) TestFetchSarifRuns_IncompatibleRunsReturnsUnrecoverable() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/incompatible_runs.sarif")

	d := s.defaultDelivery(sarifPath)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)

	s.NoError(err)

	var pe ts.ProcessError
	s.NoError(s.db.Find(&pe).Error)
	s.Contains(pe.Message, "incompatible invocations when trying to combine runs")
	s.Equal(s.sampleSarifID, pe.SarifID)
	s.Equal(ts.ProcessErrorTypeUnrecoverableDelivery, pe.ErrorType)
}

func (s *ProcessorTestSuite) TestEmitEventsOnClearedAlerts() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	d := s.defaultDelivery(sarifPath)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	s.alertEventHandler.Alerts = nil
	s.alertEventHandler.Numbers = nil
	s.alertEventHandler.Events = nil
	s.NoError(s.alertEventHandler.Flush())

	sarifPath = s.uploadFixtureFile("../sarif/testdata/empty.sarif")

	d = s.defaultDelivery(sarifPath)
	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	s.Len(s.alertEventHandler.Events, 2)
	s.Equal(ts.TimelineEventTypeAlertClosedBecameFixed, s.alertEventHandler.Events[0].EventType)
	s.Equal(ts.TimelineEventTypeAlertClosedBecameFixed, s.alertEventHandler.Events[1].EventType)
	s.Len(s.alertEventHandler.Alerts[0].PhysicalAlerts, 1)
	s.Len(s.alertEventHandler.Alerts[1].PhysicalAlerts, 1)
}

func (s *ProcessorTestSuite) TestProcessorSetsFailed() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/missing_location.sarif")
	d := s.defaultDelivery(sarifPath)

	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	as := []*ts.Analysis{}
	s.NoError(s.db.Find(&as).Error)
	s.Len(as, 1)
	s.True(as[0].Failed)

	perrs, err := s.alerts.ProcessErrors(s.ctx, d.RepositoryID, []ts.AnalysisID{as[0].ID})
	s.NoError(err)
	s.NotEmpty(perrs)
}

func (s *ProcessorTestSuite) TestDefaultRuleMetadataIsAdded() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	s.NotEmpty(analyses[0].Rules["js/unused-local-variable"].Help)
}

func (s *ProcessorTestSuite) TestDefaultRubyMetadataIsAdded() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/ruby-example.sarif")

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)

	s.NotEmpty(analyses[0].Rules["rb/overly-permissive-file"].ShortDescription)
	s.NotEmpty(analyses[0].Rules["rb/overly-permissive-file"].Help)
}

func (s *ProcessorTestSuite) TestErrorFetchingRepoMetadata() {
	mockCtrl := gomock.NewController(s.T())
	repoapi := mocks.NewMockRepositoryAPI(mockCtrl)
	s.processor.SetRepositoryAPI(repoapi)
	defer s.processor.SetRepositoryAPI(nil)

	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)

	// errors in the repo api should not cause the analysis to fail
	repoapi.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{delivery.RepositoryID}).Return(nil, errors.New("error"))
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)
	s.True(analyses[0].AnalysisComplete)

	// if no metadata was found, we still create a repository record
	repo, err := s.repos.Find(s.ctx, delivery.RepositoryID)
	s.NoError(err)
	s.NotNil(repo)
	s.Equal(delivery.RepositoryID, repo.RepositoryID)
	s.Equal([]byte(""), repo.DefaultRef)
	s.True(repo.CodeScanningEnabled)

	// a new analysis should retry fetching and updating the metadata
	expected := &ts.Repository{
		RepositoryID:        delivery.RepositoryID,
		OwnerID:             2,
		CodeScanningEnabled: true,
		SourceUpdatedAt:     sqltime.Time{Time: time.UnixMicro(2).UTC()},
		DefaultRef:          []byte("main"),
	}
	repoapi.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{expected.RepositoryID}).Return([]*ts.Repository{expected}, nil)
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)
	s.True(analyses[0].AnalysisComplete)
	repo, err = s.repos.Find(s.ctx, delivery.RepositoryID)
	s.NoError(err)
	s.NotNil(repo)
	s.Equal(expected.RepositoryID, repo.RepositoryID)
	s.Equal(expected.OwnerID, repo.OwnerID)
	s.Equal(expected.CodeScanningEnabled, repo.CodeScanningEnabled)
	s.Equal(expected.DefaultRef, repo.DefaultRef)
}

func (s *ProcessorTestSuite) TestFetchingRepoMetadata() {
	mockCtrl := gomock.NewController(s.T())
	repoapi := mocks.NewMockRepositoryAPI(mockCtrl)
	s.processor.SetRepositoryAPI(repoapi)
	defer s.processor.SetRepositoryAPI(nil)

	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)
	expected := &ts.Repository{
		RepositoryID:        delivery.RepositoryID,
		OwnerID:             2,
		CodeScanningEnabled: true,
		SourceUpdatedAt:     sqltime.Time{Time: time.UnixMicro(2).UTC()},
		DefaultRef:          []byte("main"),
	}
	repoapi.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{expected.RepositoryID}).Return([]*ts.Repository{expected}, nil)
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))
	s.NoError(err)
	s.Len(analyses, 1)
	s.True(analyses[0].AnalysisComplete)

	// fetching the repo metadata should also persist it in the database
	repo, err := s.repos.Find(s.ctx, delivery.RepositoryID)
	s.NoError(err)
	s.NotNil(repo)
	s.Equal(expected.RepositoryID, repo.RepositoryID)
	s.Equal(expected.OwnerID, repo.OwnerID)
	s.Equal(expected.CodeScanningEnabled, repo.CodeScanningEnabled)
	s.Equal(expected.DefaultRef, repo.DefaultRef)
}

// TestManagedAnalysisErrors tests that when mananged analyses are enabled,
// then any CodeQL analysis that comes from a non-dynamic workflow is blocked.
func (s *ProcessorTestSuite) TestManagedAnalysisErrors() {
	// Two kinds of workflows
	dynamic := "dynamic/github-code-scanning/codeql:analyze"
	nonDynamic := ".github/workflows/codeql:analyze"

	// Initially managed analysis is not enabled, so non-dynamic CodeQL workflows should be let through
	pe := s.uploadAndProcessByKey("../sarif/testdata/example.sarif", nonDynamic)
	s.Nil(pe)

	// Repo is enabled for managed analysis.
	s.mockMAEnablementChecker.active = true

	// Non dynamic workflows for CodeQL should be blocked
	pe = s.uploadAndProcessByKey("../sarif/testdata/example.sarif", nonDynamic)
	s.NotNil(pe)
	s.Equal("CodeQL analyses from advanced configurations cannot be processed when the default setup is enabled", pe.Message)

	// Dynamic workflows for CodeQL should still be let through
	pe = s.uploadAndProcessByKey("../sarif/testdata/example.sarif", dynamic)
	s.Nil(pe)

	// Non dynamic workflows for "CodeQL command-line toolchain" are blocked as well
	pe = s.uploadAndProcessByKey("../sarif/testdata/codeql_command_line_toolchain.sarif", nonDynamic)
	s.NotNil(pe)
	s.Equal("CodeQL analyses from advanced configurations cannot be processed when the default setup is enabled", pe.Message)

	// Both dynamic and non dynamic workflows for other tools should slip through
	pe = s.uploadAndProcessByKey("../sarif/testdata/severity.sarif", dynamic)
	s.Nil(pe)
	pe = s.uploadAndProcessByKey("../sarif/testdata/severity.sarif", nonDynamic)
	s.Nil(pe)

	// If we disable managed analysis then non-dynamic CodeQL workflows are ok again
	s.mockMAEnablementChecker.active = false
	pe = s.uploadAndProcessByKey("../sarif/testdata/example.sarif", nonDynamic)
	s.Nil(pe)
}

func (s *ProcessorTestSuite) TestCodeQLNotificationsProcessingWhenVisibilityTrue() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example-with-tool-status-notifications-visibility-true.sarif")
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))

	s.NoError(err)
	s.Len(analyses, 1)
	dbtest.RequireCount(s.T(), 1, s.db.Table("ts_analysis_messages").Where("analysis_id = ? AND `key` = ?", analyses[0].ID, "codeql-notification"))
	am := []*ts.AnalysisMessage{}
	s.NoError(s.db.Table("ts_analysis_messages").Where("analysis_id = ?", analyses[0].ID).Find(&am).Error)
	s.Equal(analyses[0].ID, *am[0].AnalysisID)
	s.Equal("codeql-notification", string(am[0].Key))
}

func (s *ProcessorTestSuite) TestCodeQLNotificationsProcessingWhenVisibilityTrueButExecutionUnsuccessful() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example-with-tool-status-notifications-visibility-true-execution-unsuccessful.sarif")
	_, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))

	s.NoError(err)
	dbtest.RequireCount(s.T(), 1, s.db.Table("ts_analysis_messages").Where("`key` = ?", "codeql-notification"))
	am := []*ts.AnalysisMessage{}
	s.NoError(s.db.Table("ts_analysis_messages").Find(&am).Error)
	s.Equal("codeql-notification", string(am[0].Key))
}

func (s *ProcessorTestSuite) TestCodeQLNotificationsProcessingWhenVisibilityFalse() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example-with-tool-status-notifications-visibility-false.sarif")
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, s.defaultDelivery(sarifPath))

	s.NoError(err)
	s.Len(analyses, 1)
	s.Empty(&analyses[0].AnalysisMessages)
	dbtest.RequireCount(s.T(), 0, s.db.Table("ts_analysis_messages").Where("analysis_id = ?", analyses[0].ID))
}

func (s *ProcessorTestSuite) uploadAndProcessByKey(fixture string, analysisKey string) *ts.ProcessError {
	// Clear process errors
	s.NoError(s.db.Delete(&ts.ProcessError{}).Error)
	sarifPath := s.uploadFixtureFile(fixture)
	d := s.defaultDelivery(sarifPath)
	d.AnalysisKey = ts.ToAnalysisKey(analysisKey)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	var pe ts.ProcessError
	err = s.db.First(&pe).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil
	}
	s.NoError(err)
	return &pe
}

// In order for 'go test' to run this suite, we need to create
// a normal test function and pass our suite to suite.Run
func TestProcessorTestSuite(t *testing.T) {
	suite.Run(t, new(ProcessorTestSuite))
}

func (s *ProcessorTestSuite) TestLastStateChangeAtOnlyChangesOnStateChange() {
	// The following cases are covered below:
	//
	// - alerts that stay open between analyses preserve lastStateChangeAt
	// - alerts that are fixed between analyses get new lastStateChangeAt
	// - alerts that stay fixed between analyses preserve lastStateChangeAt
	// - alerts that are re-opened between analyses get new lastStateChangeAt

	// defined in sarif
	constantFingerPrint := "5061c3315a741b7d:1"
	changingFingerPrint := "39fa2ee980eb94b0:1"
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")

	d := s.defaultDelivery(sarifPath)
	_, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	oPa := []*ts.PhysicalAlert{}

	s.NoError(s.db.Find(&oPa).Error)
	s.Equal(2, len(oPa))

	keyFunc := func(t *ts.PhysicalAlert) string { return t.Fingerprint }
	initialAlerts := transforms.IndexBy(oPa, keyFunc)

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")

	d = s.defaultDelivery(sarifPath)
	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	nPa := []*ts.PhysicalAlert{}

	s.NoError(s.db.Find(&nPa).Error)
	sameAlerts := transforms.IndexBy(nPa[2:], keyFunc)
	initialConstantAlert := initialAlerts[constantFingerPrint]
	// alerts that stay open between analyses preserve lastStateChangeAt
	for k, o := range initialAlerts {
		if a, ok := sameAlerts[k]; ok {
			s.Equal(o.LastStateChangeAt, a.LastStateChangeAt)
		} else {
			s.Fail("re-submitted alert does not match the previously open alert")
		}
	}

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example_without_one_physical_alert.sarif")

	d = s.defaultDelivery(sarifPath)
	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	pa := []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&pa).Error)
	oneFixedAlert := transforms.IndexBy(pa[4:], keyFunc)
	fixed := oneFixedAlert[changingFingerPrint]
	stillOpen := oneFixedAlert[constantFingerPrint]

	// alerts that are fixed between analyses get new lastStateChangeAt

	s.Greater(fixed.LastStateChangeAt.UnixMicro(), initialAlerts[changingFingerPrint].LastStateChangeAt.UnixMicro())
	s.Equal(stillOpen.LastStateChangeAt, initialConstantAlert.LastStateChangeAt)

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example_without_one_physical_alert.sarif")

	d = s.defaultDelivery(sarifPath)
	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	pa = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&pa).Error)
	stillOneFixedAlert := transforms.IndexBy(pa[6:], keyFunc)

	stillFixed := stillOneFixedAlert[changingFingerPrint]
	stillOpen = stillOneFixedAlert[constantFingerPrint]

	// alerts that stay fixed between analyses preserve lastStateChangeAt

	s.Equal(stillFixed.LastStateChangeAt, fixed.LastStateChangeAt)
	s.Equal(stillOpen.LastStateChangeAt, initialConstantAlert.LastStateChangeAt)

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")

	d = s.defaultDelivery(sarifPath)
	_, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)

	pa = []*ts.PhysicalAlert{}

	s.NoError(s.db.Find(&pa).Error)

	oneReOpenedAlert := transforms.IndexBy(pa[8:], keyFunc)

	reOpened := oneReOpenedAlert[changingFingerPrint]
	stillOpen = oneReOpenedAlert[constantFingerPrint]

	// alerts that are re-opened between analyses get new lastStateChangeAt

	s.Greater(reOpened.LastStateChangeAt.UnixMicro(), stillFixed.LastStateChangeAt.UnixMicro())
	s.Equal(stillOpen.LastStateChangeAt, initialConstantAlert.LastStateChangeAt)
}

func (s *ProcessorTestSuite) TestCopyFixesLimit() {
	// This test processes 3 analyses:
	// 1 introduces alerts
	// 2 fixes some
	// 3 again fixes some but also gets a limited amount of fixes copied from 2

	repoID := ts.RepositoryEID(992) // Repo 992 has a custom FixesCopiedLimit = 2

	ctx := flipper.WithFeatureEnabledFor(s.ctx, "code_scanning_limit_alert_fixes", repoID)

	// Prepare some filters for later
	openAlertsFilter := ts.AlertFilter{
		State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN,
	}
	fixedAlertsFilter := ts.AlertFilter{
		State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED,
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: repoID,
		State:        ts.AnalysisStateFilterMostRecent,
	}

	// Process the first delivery, introducing 5 alerts
	sarifPath := s.uploadFixtureFile("../sarif/testdata/copied_fixes_limit_test_1.sarif")
	d := s.defaultDelivery(sarifPath)
	d.RepositoryID = repoID
	_, err := s.processor.ProcessNewDelivery(ctx, d)
	s.NoError(err)
	openAlerts, err := s.alerts.PhysicalAlerts(ctx, d.RepositoryID, openAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	s.Require().Equal(5, len(openAlerts))
	fixedAlerts, err := s.alerts.PhysicalAlerts(ctx, d.RepositoryID, fixedAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	s.Require().Equal(0, len(fixedAlerts))

	// Process the second delivery.
	// It maintains two alerts, 3 alerts in a generated file disappear and 3 in a different file appear.
	sarifPath = s.uploadFixtureFile("../sarif/testdata/copied_fixes_limit_test_2.sarif")
	d = s.defaultDelivery(sarifPath)
	d.RepositoryID = repoID
	_, err = s.processor.ProcessNewDelivery(ctx, d)
	s.NoError(err)
	openAlerts, err = s.alerts.PhysicalAlerts(ctx, d.RepositoryID, openAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	s.Require().Equal(5, len(openAlerts))
	fixedAlerts, err = s.alerts.PhysicalAlerts(ctx, d.RepositoryID, fixedAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	s.Require().Equal(3, len(fixedAlerts))

	// Process the third delivery.
	// It maintains the same two alerts as before and again fixes 3 in a generated file
	// and introduces 3 in another generated file.
	sarifPath = s.uploadFixtureFile("../sarif/testdata/copied_fixes_limit_test_3.sarif")
	d = s.defaultDelivery(sarifPath)
	d.RepositoryID = repoID
	_, err = s.processor.ProcessNewDelivery(ctx, d)
	s.NoError(err)
	openAlerts, err = s.alerts.PhysicalAlerts(ctx, d.RepositoryID, openAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	s.Require().Equal(5, len(openAlerts))
	fixedAlerts, err = s.alerts.PhysicalAlerts(ctx, d.RepositoryID, fixedAlertsFilter, analysisFilter, nil)
	s.NoError(err)
	// If all fixes had been copied we would have 6 fixed alerts (3 newly fixed + 3 copied fixes)
	// But for the repo we actually have a limit of copying maximally 2 fixes
	s.Require().Equal(5, len(fixedAlerts))
}

func (s *ProcessorTestSuite) TestProcessNewBuild_WithCodeQLErrors() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/codeql_extractor_errors.sarif")
	delivery := s.defaultDelivery(sarifPath)

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	messages := []*ts.AnalysisExtractedFilesMessages{}
	s.Require().NoError(s.db.Find(&messages).Error)
	s.Require().Len(messages, 2)

	messagesByPath := transforms.IndexBy(messages, func(m *ts.AnalysisExtractedFilesMessages) string {
		return m.Path
	})
	// keys of messagesByPath should be file.py and file2.py
	// file3.py should not be in the messagesByPath map since its message is empty
	s.Require().ElementsMatch([]string{"file.py", "file2.py"}, maps.Keys(messagesByPath))

	s.Require().Equal(
		"A parse error occurred while processing `file.py`, and as a result this file could not be analyzed. Check the syntax of the file using the `python -m py_compile` command and correct any invalid syntax.",
		messagesByPath["file.py"].Message)
	s.Require().Equal(
		"This is a warning message about `file2.py`.",
		messagesByPath["file2.py"].Message)

	for _, m := range messages {
		s.Require().Equal(delivery.RepositoryID, m.RepositoryID)
		s.Require().Equal(analyses[0].ID, m.AnalysisID)
	}
}

func (s *ProcessorTestSuite) TestProcessedSARIF() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	as := []*ts.Analysis{}
	s.NoError(s.db.Find(&as).Error)
	s.Require().Len(as, 1)
	s.Require().NotEmpty(as[0].ArchivalDataUrl)
	s.Require().True(s.sarifs.Exists(s.ctx, as[0].ArchivalDataUrl))
	s.Require().True(as[0].AnalysisComplete)
	s.Require().False(as[0].Failed)

	// try a SARIF with no alerts (fixing all previous ones)
	sarifPath = s.uploadFixtureFile("../sarif/testdata/empty.sarif")
	delivery = s.defaultDelivery(sarifPath)

	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	as = []*ts.Analysis{}
	s.NoError(s.db.Last(&as).Error)
	s.Require().Len(as, 1)
	s.Require().NotEmpty(as[0].ArchivalDataUrl)
	s.Require().True(s.sarifs.Exists(s.ctx, as[0].ArchivalDataUrl))
	s.Require().True(as[0].AnalysisComplete)
	s.Require().False(as[0].Failed)
}

func (s *ProcessorTestSuite) TestProcessedSARIFToolVersions() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/multi_extensions.sarif")
	delivery := s.defaultDelivery(sarifPath)

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	as := []*ts.Analysis{}
	s.NoError(s.db.Find(&as).Error)
	s.Require().Len(as, 1)
	s.Require().NotEmpty(as[0].ArchivalDataUrl)
	s.Require().True(s.sarifs.Exists(s.ctx, as[0].ArchivalDataUrl))
	s.Require().True(as[0].AnalysisComplete)
	s.Require().False(as[0].Failed)
}

func (s *ProcessorTestSuite) TestFailedProcessedSARIF() {
	sarifPath := "../sarif/testdata/example.sarif"
	f, err := os.ReadFile(sarifPath)
	s.NoError(err)
	sarif := bytes.NewBuffer(f)

	uploadErr := errors.New("failed to upload SARIF")
	mockStore := mocks.NewMockSarifStore(gomock.NewController(s.T()))
	mockStore.EXPECT().Download(gomock.Any(), gomock.Any()).Return(sarif, nil)                 // download the original SARIF
	mockStore.EXPECT().Archive(gomock.Any(), gomock.Any(), gomock.Any()).Return("", uploadErr) // upload the processed SARIF

	origStore := s.sarifs
	s.sarifs = mockStore
	defer func() {
		s.sarifs = origStore
	}()
	s.processor = processor.New(s.alerts, s.analyses, s.ds, s.ams, s.sarifs, s.sarifs, s.tools, s.configurations, s.rules, s.timelines, s.repos, nil, s.ls, s.rma, s.mockMAEnablementChecker, s.alertEventHandler, s.jobs)

	delivery := s.defaultDelivery(sarifPath)

	_, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().ErrorIs(err, uploadErr)

	// Upload errros should not be unrecoverable
	var perr *ts.ProcessError
	s.Require().False(errors.As(err, &perr))

	as := []*ts.Analysis{}
	s.NoError(s.db.Find(&as).Error)
	s.Require().Len(as, 1)
	s.Require().Empty(as[0].ArchivalDataUrl)

	s.Require().True(as[0].AnalysisComplete)
	s.Require().True(as[0].Failed)
}

func (s *ProcessorTestSuite) TestStoringAnalysisRulesAndToolVersions() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)

	// by default, we should no longer be saving AnalysisRules and AnalysisToolVersions
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a := &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	emptyRules := []*ts.AnalysisRule{}
	s.NoError(s.db.Find(&emptyRules, "analysis_id=?", a.ID).Error)
	s.Require().Len(emptyRules, 0)

	emptyTools := []*ts.AnalysisToolVersion{}
	s.NoError(s.db.Find(&emptyTools, "analysis_id=?", a.ID).Error)
	s.Require().Len(emptyTools, 0)
}

func (s *ProcessorTestSuite) Test_UpdateLogicalAlertFields() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)

	// Ensure that we are on the default ref for the initial delivery
	s.NoError(s.db.Create(&ts.Repository{RepositoryID: delivery.RepositoryID, DefaultRef: delivery.Ref, SourceUpdatedAt: sqltime.Now()}).Error)

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a := &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts := []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts := []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	originalMessages := make(map[ts.LogicalAlertID]string)

	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().Equal(a.ConfigurationID, la.DefaultConfigurationID)
		s.Require().NotEmpty(la.Region)
		originalMessages[la.ID] = la.Message
	}

	// Use the SARIF with same alerts but different messages on default ref again so the instance information changes
	sarifPath = s.uploadFixtureFile("../sarif/testdata/example-new-messages.sarif")
	delivery = s.defaultDelivery(sarifPath)
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a = &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts = []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById = transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	newMessages := make(map[ts.LogicalAlertID]string)

	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		s.Require().Equal(a.ConfigurationID, la.DefaultConfigurationID)
		// the messages should have changed
		s.Require().NotEqual(originalMessages[la.ID], la.Message)
		newMessages[la.ID] = la.Message
	}

	// Use the original SARIF again, but as we are not on default ref the instance information will not be updated
	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery = s.defaultDelivery(sarifPath)
	delivery.Ref = []byte("refs/heads/not-main")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a = &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts = []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById = transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		configID := a.ConfigurationID
		// The logical alert default configuration should not be the same as the analysis configuration
		s.Require().NotEqual(configID, la.DefaultConfigurationID)
		// the messages should not have changed even
		s.Require().Equal(newMessages[la.ID], la.Message)
	}
}

func (s *ProcessorTestSuite) Test_UpdateLogicalAlertsFields_NonDefaultOverwrites() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery := s.defaultDelivery(sarifPath)
	delivery.Ref = []byte("refs/heads/not-default")
	defaultRef := []byte("refs/heads/default-ref")
	// Ensure that we are NOT on the default ref for the initial delivery
	s.NoError(s.db.Create(&ts.Repository{RepositoryID: delivery.RepositoryID, DefaultRef: defaultRef, SourceUpdatedAt: sqltime.Now()}).Error)

	analyses, err := s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a := &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts := []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts := []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	originalMessages := make(map[ts.LogicalAlertID]string)
	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		s.Require().Equal(a.ConfigurationID, la.DefaultConfigurationID)
		originalMessages[la.ID] = la.Message
	}

	// Use the SARIF with same alerts but different messages on another ref so the instance information changes
	sarifPath = s.uploadFixtureFile("../sarif/testdata/example-new-messages.sarif")
	delivery = s.defaultDelivery(sarifPath)
	delivery.Ref = []byte("refs/heads/something-else")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a = &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts = []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById = transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	repositories := []*ts.Repository{}
	s.NoError(s.db.Find(&repositories, "repository_id=?", a.RepositoryID).Error)

	newMessages := make(map[ts.LogicalAlertID]string)

	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		s.Require().Equal(a.ConfigurationID, la.DefaultConfigurationID)
		// the messages should have changed
		s.Require().NotEqual(originalMessages[la.ID], la.Message)
		newMessages[la.ID] = la.Message
	}

	// Use the original SARIF again, on default ref and instance information will be updated
	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")
	delivery = s.defaultDelivery(sarifPath)
	delivery.Ref = defaultRef
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a = &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts = []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById = transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	var defaultConfigurationID ts.ConfigurationID
	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		s.Require().Equal(a.ConfigurationID, la.DefaultConfigurationID)
		// store the new configuration ID as it now points at the default ref
		defaultConfigurationID = la.DefaultConfigurationID
		// the messages have changed
		s.Require().Equal(originalMessages[la.ID], la.Message)
	}

	// Use the SARIF with same alerts but different messages on non-default ref but now we have a default ref analysis, the instance info will not change
	sarifPath = s.uploadFixtureFile("../sarif/testdata/example-new-messages.sarif")
	delivery = s.defaultDelivery(sarifPath)
	delivery.Ref = []byte("refs/heads/something-else")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, delivery)
	s.Require().NoError(err)
	s.Require().Len(analyses, 1)

	a = &ts.Analysis{}
	s.NoError(s.db.Last(&a).Error)

	physicalAlerts = []*ts.PhysicalAlert{}
	s.NoError(s.db.Find(&physicalAlerts, "repository_id=? AND analysis_id=?", a.RepositoryID, a.ID).Error)
	s.Require().Len(physicalAlerts, 2)

	logicalAlerts = []*ts.LogicalAlert{}
	s.NoError(s.db.Find(&logicalAlerts, "repository_id=?", a.RepositoryID).Error)
	s.Require().Len(logicalAlerts, 2)

	logicalAlertsById = transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	for _, pa := range physicalAlerts {
		la := logicalAlertsById[pa.LogicalAlertID]
		s.Require().Empty(pa.FilePath)
		s.Require().NotEmpty(la.FilePath)
		s.Require().Empty(pa.Message)
		s.Require().NotEmpty(la.Message)
		s.Require().NotEmpty(la.Region)
		// Should still be the default confiuration ID
		s.Require().NotEqual(a.ConfigurationID, la.DefaultConfigurationID)
		s.Require().Equal(defaultConfigurationID, la.DefaultConfigurationID)
		// the messages should not have changed
		s.Require().Equal(originalMessages[la.ID], la.Message)
	}
}

func (s *ProcessorTestSuite) TestNonUniqueAlertEvents() {
	sarifPath := s.uploadFixtureFile("../sarif/testdata/example.sarif")
	d := s.defaultDelivery(sarifPath)
	analyses, err := s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Len(s.alertEventHandler.Events, 2)
	for _, event := range s.alertEventHandler.Events {
		s.False(event.NonUnique)
	}

	s.alertEventHandler.Reset(s)

	sarifPath = s.uploadFixtureFile("../sarif/testdata/example.sarif")
	d = s.defaultDelivery(sarifPath)
	d.Ref = []byte("a-different-ref")
	analyses, err = s.processor.ProcessNewDelivery(s.ctx, d)
	s.NoError(err)
	s.Len(analyses, 1)
	s.Len(s.alertEventHandler.Events, 2)
	for _, event := range s.alertEventHandler.Events {
		s.True(event.NonUnique)
	}

	s.alertEventHandler.Reset(s)
}
