// Package cassettes provides logic for recording VCR cassettes and manipulating Turboscan state.
package cassettes

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/auditlog"

	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/botfetcher"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mysql/alertlink"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/github/turboscan/ts/processor"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	insightshydroentities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turbocassette/recorder"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/limits"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/pr_alerts"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/test_helpers"
	"github.com/github/turboscan/ts/twirp"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	twirp_ma "github.com/github/turboscan/ts/twirp/managed_analyses"
	twirp_sf "github.com/github/turboscan/ts/twirp/suggested_fixes"
	"github.com/github/turboscan/ts/workflows"

	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	twitch_twirp "github.com/twitchtv/twirp"
)

// Session is the struct responsible for encapsulating the state of the
// system under test.
type Session struct {
	ctx                    context.Context
	logger                 log.Logger
	limitSelector          *limits.LimitSelector
	statsClient            stats.Client
	reporter               *exceptions.Reporter
	db                     *gorm.DB
	sarifUploader          store.SarifStore
	repositoryService      *repository.Service
	alertService           *alert.Service
	archiveService         *archiver.Service
	deliveryService        *delivery.Service
	managedAnalysisService *managedanalysis.Service
	suggestedFixesService  *sf.SuggestedFixes
	enabledStatusService   *enabled_status.EnabledStatusService
	processor              *processor.Processor
	search                 *elasticsearch.Service
	handler                http.Handler
	now                    time.Time
	recorder               *recorder.Recorder
	templateLibrary        *workflows.Library
	aqueduct               *sessionAqueduct
	aqueductServices       *aqueduct.TSServices
	cfg                    *config.Config
}

// NewSession returns a regular Turboscansvc session
func NewSession(t *testing.T) *Session {
	t.Helper()
	return newSession(t, false, nil)
}

// NewSessionWithES returns a Turboscansvc session with ElasticSearch enabled
func NewSessionWithES(t *testing.T) *Session {
	t.Helper()
	return newSession(t, true, nil)
}

// NewSessionWithConfigOverride returns a Turboscansvc session with the config overridden by the provided function, f
func NewSessionWithConfigOverride(t *testing.T, f func(config *config.Config)) *Session {
	t.Helper()
	return newSession(t, false, f)
}

func newSession(t *testing.T, enableSearch bool, f func(config *config.Config)) *Session {
	t.Helper()

	cfg, err := config.Load()
	require.NoError(t, err)
	if f != nil {
		f(cfg)
	}

	cfg.LogLevel = "error"
	logger, err := cfg.NewLogger()
	require.NoError(t, err)

	statsClient := cfg.NewStatsClient("cassettes")
	reporter := test_helpers.NewExceptionReporter(t)

	ctx := appctx.WithReporter(context.Background(), reporter)

	db := dbtest.RequireConnectionWithoutAutoIncrement(t)

	sarifStore := store.NewSarifStore(config.STORAGE_MEMORY, cfg)
	require.NoError(t, sarifStore.Open(context.Background()))

	archivalStore, err := archivalstore.NewArchivalStoreFromConfig(sarifStore, cfg)
	require.NoError(t, err)

	t.Cleanup(func() {
		require.NoError(t, sarifStore.Close(context.Background()))
	})

	limitSelector := limits.NewLimitSelector(cfg.Limits(), cfg.DisableSarifHardLimit)

	alertHandler := &loggingAlertHandler{
		logger: logger,
	}
	insightsHandler := &loggingInsightsHandler{
		logger: logger,
	}

	alertService := alert.TestService(db)
	var searchService *elasticsearch.Service
	if enableSearch {
		searchService = elasticsearch.SetUpTestElasticSearchService(t)
	}

	alertLinkService := alertlink.NewService(db)
	alertLinksService := alertlinks.NewService(alertLinkService, &mockHydroPublisher{}, searchService)
	repositoryService := repository.NewService(db)
	archiveService := archiver.NewService(db, archivalStore)
	timelineEventService := timeline.NewService(db)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	configurationService := configuration.NewService(db)
	ruleService := rule.NewService(db)
	analysisService := analysis.NewService(db)
	deliveryService := delivery.NewService(db)
	prAlertsService := pr_alerts.NewService(db)
	managedAnalysisService := managedanalysis.NewService(db, &mockHydroPublisher{})
	suggestedFixesService := suggestedfixes.NewService(db)
	enabledStatusService := enabled_status.NewEnabledStatusService(db, alertService, repositoryService, managedAnalysisService, &mockHydroPublisher{}, true)
	analysisMessageService := analysismessage.NewService(db)

	rma, err := sarif.DefaultRuleMetadataAugmentor()
	require.NoError(t, err)

	rAqueduct, err := recorder.NewAsMode("../../twirp/clients/aqueduct/testdata/aqueduct.yml", recorder.ModeReplaying, nil)
	require.NoError(t, err)
	sessionAqueduct, err := NewSessionAqueduct(cfg, logger, statsClient, rAqueduct)
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, rAqueduct.Stop())
	})

	processor := processor.New(alertService, analysisService, deliveryService, analysisMessageService, sarifStore, archivalStore, toolService, configurationService, ruleService, timelineEventService, repositoryService, nil, limitSelector, rma, managedAnalysisService, nil, sessionAqueduct)
	require.NoError(t, err)

	// TODO: Extend the Recorder so that we can load different cassettes for each test
	rLaunch, err := recorder.NewAsMode("../../twirp/clients/actions/testdata/launch.yml", recorder.ModeReplaying, nil)
	require.NoError(t, err)
	launchClient, err := actions.New(cfg, actions.WithDebugClient(rLaunch))
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, rLaunch.Stop())
	})

	rr := twirp.NewResultsResolver(alertService, alertLinksService, prAlertsService, deliveryService, timelineEventService, toolService, repositoryService, suggestedFixesService, analysisMessageService, archiveService, sarifStore, archivalStore, searchService, alertHandler, insightsHandler, sessionAqueduct, enabledStatusService, false)

	templateLibrary := workflows.NewLibrary(workflows.WithDefaultNonGHHostedRunnerLabel(cfg.ActionsDefaultNonGitHubHostedRunnerLabel()))

	maLogicService := &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: mockMATwirp{},
		DataService:          managedAnalysisService,
		LaunchApiClient:      launchClient,
		UpdateRepoMetadata:   func(ctx context.Context, repoID ts.RepositoryEID) error { return nil },
		WorkflowsLibrary:     templateLibrary,
		EnabledStatusService: enabledStatusService,
		GetBotActor:          botfetcher.Static(ts.ActorGRIDLogin{GRID: "grid", Login: "bot"}),
		Scheduler:            managedanalyses.NewScheduler(true),
	}
	maTwirp := twirp_ma.New(maLogicService, cfg.JavaBuildlessDisabled, cfg.CSharpBuildlessDisabled, cfg.CppBuildlessDisabled)

	publishStateChange := func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		_, _ = sessionAqueduct.PerformLater(ctx, &jobs.AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		})
	}

	sfLogicService := &sf.SuggestedFixes{
		FixGenerator:                        sf.NewMockValidFixGenerator(),
		GitHubTwirpApiClient:                mockSFTwirp{},
		DbService:                           suggestedFixesService,
		AlertService:                        alertService,
		ArchiveService:                      archiveService,
		SpokesClient:                        &spokes.MockSpokes{},
		LimitsSelector:                      limits.NewLimitSelector(nil, false),
		SyncUpdate:                          publishStateChange,
		AutofixGeneratePublisher:            &mockHydroPublisher{},
		AutofixGenerationCompletedPublisher: &mockHydroPublisher{},
	}
	sfTwirp := twirp_sf.New(sfLogicService, sarifStore, sessionAqueduct, searchService)

	// The option WithServerJSONCamelCaseNames is used to ensure that the fields in the cassette
	// match the Ruby serializer, otherwise the default is to use snake_case.
	handler := app.Handler(
		rr,
		rr,
		maTwirp,
		sfTwirp,
		twitch_twirp.WithServerJSONCamelCaseNames(true),
	)

	aqueductServices := &aqueduct.TSServices{
		ManagedAnalyses: maLogicService,
		SuggestedFixes:  sfLogicService,
		Aqueduct:        sessionAqueduct,
		IsEnterpriseEnv: cfg.IsEnterpriseEnv(),
	}

	return &Session{
		ctx:                    ctx,
		limitSelector:          limitSelector,
		db:                     db,
		sarifUploader:          sarifStore,
		repositoryService:      repositoryService,
		alertService:           alertService,
		archiveService:         archiveService,
		managedAnalysisService: managedAnalysisService,
		suggestedFixesService:  sfLogicService,
		enabledStatusService:   enabledStatusService,
		statsClient:            statsClient,
		reporter:               reporter,
		logger:                 logger,
		processor:              processor,
		deliveryService:        deliveryService,
		search:                 searchService,
		handler:                handler,
		now:                    time.Now(),
		recorder:               rLaunch,
		templateLibrary:        templateLibrary,
		aqueduct:               sessionAqueduct,
		aqueductServices:       aqueductServices,
		cfg:                    cfg,
	}

}

type mockMATwirp struct {
	ghgh.ManagedAnalysesAPI
}

func (mockMATwirp) GetCodeScanningBotInfo(ctx context.Context) (*ts.ActorGRIDLogin, error) {
	return &ts.ActorGRIDLogin{
		GRID:  ts.ActorGRID("botGRID"),
		Login: "botLogin",
	}, nil
}

type mockSFTwirp struct {
	ghgh.SuggestedFixesAPI
}

func (mockSFTwirp) SuggestedFixStateChanged(ctx context.Context, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers []uint32) error {
	return nil
}

type mockHydroPublisher struct{}

func (*mockHydroPublisher) EnablementEvent(ctx context.Context, m *tshydro.EnablementEvent) error {
	return nil
}

func (*mockHydroPublisher) AlertLinksCreateBatch(ctx context.Context, messages []*tshydro.AlertLinkCreate) error {
	return nil
}

func (*mockHydroPublisher) AlertLinksUpdateBatch(ctx context.Context, messages []*tshydro.AlertLinkUpdate) error {
	return nil
}

func (*mockHydroPublisher) AutofixGenerateEventBatch(_ context.Context, _ []*tshydro.AutofixGenerateEvent) error {
	return nil
}

func (*mockHydroPublisher) AutofixGenerationCompletedEvent(ctx context.Context, m *tshydro.AutofixGenerationCompleted) error {
	return nil
}

func (p *mockHydroPublisher) CodeqlRunEvent(_ context.Context, m *oldtshydro.CodeqlRun) error {
	return nil
}

func (session *Session) PerformJob(t *testing.T, queue string) {
	t.Helper()

	q := session.aqueduct.queue[queue]
	require.NotEmpty(t, q)

	// pop the job
	job, q := q[0], q[1:]
	session.aqueduct.queue[queue] = q

	err := job.Perform(session.ctx, session.aqueductServices)
	require.NoError(t, err)
}

type sessionAqueduct struct {
	aqueduct.Client

	client *aqueduct.Client
	queue  map[string][]aqueduct.EnqueableJob
}

func (a *sessionAqueduct) enqueue(j aqueduct.EnqueableJob) {
	q := a.queue[j.Queue()]
	q = append(q, j)
	a.queue[j.Queue()] = q
}

func (a *sessionAqueduct) PerformLater(ctx context.Context, j aqueduct.EnqueableJob) (string, error) {
	a.enqueue(j)
	return a.client.PerformLater(ctx, j)
}

func (a *sessionAqueduct) PerformLaterAt(ctx context.Context, j aqueduct.EnqueableJob, at time.Time) (string, error) {
	a.enqueue(j)
	return a.client.PerformLaterAt(ctx, j, at)
}

func (a *sessionAqueduct) RetryLater(ctx context.Context, j aqueduct.EnqueableJob, retryCount uint8) (string, error) {
	a.enqueue(j)
	return a.client.RetryLater(ctx, j, retryCount)
}

func NewSessionAqueduct(cfg *config.Config, logger log.Logger, stats stats.Client, rt http.RoundTripper) (*sessionAqueduct, error) {
	client, err := aqueduct.NewClient(cfg, logger, stats, rt)
	if err != nil {
		return nil, err
	}

	return &sessionAqueduct{
		client: client,
		queue:  make(map[string][]aqueduct.EnqueableJob),
	}, nil
}

// WithFeatureEnabled enables a feature for the duration of the session.
func (session *Session) WithFeatureEnabled(feature string) *Session {
	session.ctx = flipper.WithFeatureEnabled(session.ctx, feature)
	return session
}

// WithFeatureDisabled disables a feature for the duration of the session.
func (session *Session) WithFeatureDisabled(feature string) *Session {
	session.ctx = flipper.WithFeatureDisabled(session.ctx, feature)
	return session
}

type loggingAlertHandler struct {
	logger log.Logger
}

func (ah loggingAlertHandler) NewAlertEvent(ctx context.Context, la *ts.LogicalAlert, event *ts.TimelineEvent) error {
	ah.logger.Info(fmt.Sprintf("A new alert was created with id %d in repository: %d", la.ID, event.RepositoryID))
	return nil
}

func (ah loggingAlertHandler) NewAuditEvents(ctx context.Context, batch ts.AuditEntryBatch, auditLogContext auditlog.AuditLogContext) error {
	ah.logger.Info(fmt.Sprintf("A new audit log batch was created with %d events in repository: %d", len(batch.AlertNumbers), batch.RepositoryID))
	return nil
}

func (ah loggingAlertHandler) Flush() error {
	ah.logger.Info("Flushing alert handler")
	return nil
}

type loggingInsightsHandler struct {
	logger log.Logger
}

func (ih loggingInsightsHandler) EmitInsightsEvents(ctx context.Context, docs []*ts.SearchDocument, changedLogicalAlertIds map[ts.LogicalAlertID]struct{}) error {
	ih.logger.Info(fmt.Sprintf("EmitInsightsEvents was called with %d documents", len(docs)))
	return nil
}

func (ih loggingInsightsHandler) NewInsightsEntityBatchEvent(ctx context.Context, docs []*ts.SearchDocument, event_time time.Time) error {
	ih.logger.Info(fmt.Sprintf("A new insights entity batch event was created with %d documents", len(docs)))
	return nil
}

func (ih loggingInsightsHandler) GetAlertFieldsHash(ctx context.Context, doc *ts.SearchDocument, event_time time.Time) *insightshydroentities.InsightsData {
	ih.logger.Info(fmt.Sprintf("GetAlertFieldsHash was called with alert number %d", doc.Number))
	return &insightshydroentities.InsightsData{}
}

// MarkLastAnalysisAsIncomplete fetches the last inserted analysis and marks it
// as incomplete.
func (session *Session) MarkLastAnalysisAsIncomplete(t *testing.T) {
	t.Helper()
	var analysis ts.Analysis
	err := session.db.Last(&analysis).Error
	require.NoError(t, err)

	analysis.AnalysisComplete = false
	analysis.MostRecent = false
	err = session.db.Save(&analysis).Error
	require.NoError(t, err)
}

// DeleteProcessErrorForLastAnalysis deletes the process errors associated with
// the last inserted analysis.
func (session *Session) DeleteProcessErrorForLastAnalysis(t *testing.T) {
	t.Helper()
	var analysis2 ts.Analysis
	err := session.db.Last(&analysis2).Error
	require.NoError(t, err)

	err = session.db.Where("analysis_id = ?", analysis2.ID).Delete(&ts.ProcessError{}).Error
	require.NoError(t, err)
}

// ResolveAllAlerts marks all alerts for the repo resolved as false positive
func (session *Session) ResolveAllAlerts(t *testing.T, repoID ts.RepositoryEID) {
	t.Helper()

	err := session.db.
		Model(ts.LogicalAlert{}).
		Where(&ts.LogicalAlert{RepositoryID: repoID}).
		Update(map[string]interface{}{"resolution": ts.AlertResolutionFalsePositive}).
		Error
	require.NoError(t, err)
}

// ResolveAlert marks an alert for the repo as false positive
func (session *Session) ResolveAlert(t *testing.T, repoID ts.RepositoryEID, alertNumber uint32) {
	t.Helper()

	err := session.db.
		Model(ts.LogicalAlert{}).
		Where(&ts.LogicalAlert{RepositoryID: repoID, Number: alertNumber}).
		Update(map[string]interface{}{"resolution": ts.AlertResolutionFalsePositive}).
		Error
	require.NoError(t, err)
}

// ArchiveNotMostRecent will archive every analysis that is not most recent.
func (session *Session) ArchiveNotMostRecent(t *testing.T) {
	t.Helper()

	var rows []struct {
		AnalysisID   ts.AnalysisID
		RepositoryID ts.RepositoryEID
	}
	err := session.db.Table("ts_analyses").Where("NOT most_recent").Select("id AS analysis_id, repository_id").Find(&rows).Error
	require.NoError(t, err)
	require.Greater(t, len(rows), 0, "attempted to archive with no suitable analyses")

	for _, row := range rows {
		err = session.archiveService.FullArchive(session.ctx, row.RepositoryID, row.AnalysisID, archiver.ArchiveOpts{Delete: true})
		require.NoError(t, err)
	}
}

// ArchiveAll will archive every analysis, making them not most recent in the process.
func (session *Session) ArchiveAll(t *testing.T) {
	t.Helper()

	err := session.db.Model(&ts.Analysis{}).Update("most_recent", false).Error
	require.NoError(t, err)

	session.ArchiveNotMostRecent(t)
}

// ArchiveAnalysis archives the given analysis, marking it as not most recent in the process
func (session *Session) ArchiveAnalysis(t *testing.T, repoID ts.RepositoryEID, analysisID ts.AnalysisID) {
	t.Helper()

	err := session.db.Model(&ts.Analysis{}).Where("id = ?", analysisID).Update("most_recent", false).Error
	require.NoError(t, err)

	err = session.archiveService.FullArchive(session.ctx, repoID, analysisID, archiver.ArchiveOpts{Delete: true})
	require.NoError(t, err)
}

func (session *Session) UpsertCodeqlRunStatus(t *testing.T, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID, status ts.CodeqlRunStatus) {
	t.Helper()
	_, err := session.aqueductServices.ManagedAnalyses.UpsertCodeqlRunStatus(session.ctx, repoID, workflowRunID, "sha", status)
	require.NoError(t, err)
}

// CreateCurrentCodeqlConfig creates a new CURRENT CodeqlConfig for the given repoID.
// It makes also makes sure the config has a successful validation run associated with it.
func (session *Session) CreateCurrentCodeqlConfig(t *testing.T, repoID ts.RepositoryEID) {
	t.Helper()
	// TODO: This should not modify the DB directly but use existing methods from ManagedAnalysis.
	template := session.templateLibrary.GetWorkflowTemplate(session.ctx, repoID)
	completedStatus := ts.CodeqlRunStatus_COMPLETED
	config := &ts.CodeqlConfig{
		RepositoryID:           repoID,
		OnboardedByActorGRID:   "123abc",
		CreatedByActorLogin:    "abc",
		Languages:              []string{"javascript-typescript"},
		InitialLanguages:       []string{"javascript-typescript"},
		ValidationRunStatus:    &completedStatus,
		TemplateVersion:        template.Version,
		UsingCombinedLanguages: true,
	}
	config.MakeCurrent()
	err := session.db.Save(config).Error
	require.NoError(t, err)

	run := &ts.CodeqlRun{
		RepositoryID:   repoID,
		WorkflowRunID:  5,
		CodeqlConfigID: config.ID,
		Status:         ts.CodeqlRunStatus_COMPLETED,
		RunType:        ts.CodeqlRunType_VALIDATION,
	}
	err = session.db.Save(run).Error
	require.NoError(t, err)

	err = session.managedAnalysisService.CreateCodeqlSchedule(session.ctx, repoID, time.Now().Add(time.Minute*time.Duration(15)))
	require.NoError(t, err)

	// Create only creates a bare entry
	err = session.managedAnalysisService.CreateCodeqlRepo(
		session.ctx,
		&ts.CodeqlRepo{
			RepositoryID:        repoID,
			SupportedLanguages:  config.Languages,
			EnabledByActorLogin: config.CreatedByActorLogin,
		},
	)
	require.NoError(t, err)
	codeqlRepo, err := session.managedAnalysisService.GetCodeqlRepo(session.ctx, repoID)
	require.NoError(t, err)
	codeqlRepo.CurrentConfigID = &config.ID
	err = session.managedAnalysisService.UpdateCodeqlRepo(session.ctx, codeqlRepo)
	require.NoError(t, err)
}

func (session *Session) MarkCodeqlConfigsAsNotUsingCombinedLanguages(t *testing.T, repoID ts.RepositoryEID) {
	t.Helper()

	err := session.db.Model(&ts.CodeqlConfig{}).Where("repository_id = ?", repoID).Update("using_combined_languages", false).Error
	require.NoError(t, err)

	err = session.db.Model(&ts.CodeqlRepo{}).Where("repository_id = ?", repoID).Update("using_combined_languages", false).Error
	require.NoError(t, err)
}

func (session *Session) ChangeCodeqlRunWorkflowRunId(t *testing.T) {
	t.Helper()

	err := session.db.Model(&ts.CodeqlRun{}).Where("workflow_run_id = ?", 5).Update("workflow_run_id", 4).Error
	require.NoError(t, err)
}

func (session *Session) CreateSuggestedFix(t *testing.T, repoID ts.RepositoryEID, alertNumber uint32, physicalAlertID ts.PhysicalAlertID, description string, fileDiffs [][]byte, commit string, ref string, dependencyMetadata ts.SuggestedFixDependencyMetadata) {
	t.Helper()

	sf := &ts.SuggestedFix{
		RepositoryID: repoID,
		AiVersion:    "test",
		AiModel:      "test",
		Description:  description,
	}

	if dependencyMetadata != nil {
		sf.DependencyMetadata = dependencyMetadata
	}

	stateTime := sqltime.Now()
	refBytes := []byte(ref)
	var logicalAlert ts.LogicalAlert
	err := session.db.Table("ts_logical_alerts").Where("repository_id = ? AND number = ?", repoID, alertNumber).First(&logicalAlert).Error
	require.NoError(t, err)

	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        repoID,
		LogicalAlertNumber:  alertNumber,
		SuggestedFix:        sf,
		State:               ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:      stateTime,
		RefBytes:            refBytes,
		RuleSarifIdentifier: logicalAlert.SarifIdentifier,
		RequestedAt:         stateTime,
	}

	files := []*ts.SuggestedFixFile{}
	for _, diff := range fileDiffs {
		diffString := string(diff)
		lines := strings.Split(diffString, "\n")
		firstLine := lines[0]

		var path string

		if strings.HasPrefix(firstLine, "--- a/") {
			path = strings.TrimPrefix(firstLine, "--- a/")
		} else if strings.HasPrefix(firstLine, "--- ") {
			path = strings.TrimPrefix(firstLine, "--- ")
		}
		content := []byte("some content")
		files = append(files, &ts.SuggestedFixFile{
			RepositoryID: repoID,
			FilePath:     path,
			FilePathHash: ts.BuildFilePathHash(path),
			FileChecksum: ts.BuildFileChecksum(content),
			DiffContent:  diff,
		})
		ss, ok := session.suggestedFixesService.SpokesClient.(*spokes.MockSpokes)
		require.True(t, ok)
		ss.AddFile(spokes.Filename(path), spokes.CommitOID(commit), content)
	}
	sf.Files = files

	err = session.suggestedFixesService.DbService.CreateSuggestedFix(session.ctx, sfa)
	require.NoError(t, err)
}

func (session *Session) MockSuggestedFixFile(t *testing.T, path string, commit string, content []byte) {
	t.Helper()

	ss, ok := session.suggestedFixesService.SpokesClient.(*spokes.MockSpokes)
	require.True(t, ok)
	ss.AddFile(spokes.Filename(path), spokes.CommitOID(commit), content)
}

func (session *Session) CreateEmptySuggestedFix(t *testing.T, repoID ts.RepositoryEID, alertNumber uint32, physicalAlertID ts.PhysicalAlertID, ref string, state ts.SuggestedFixAlertState) {
	t.Helper()

	var logicalAlert ts.LogicalAlert
	err := session.db.Table("ts_logical_alerts").Where("repository_id = ? AND number = ?", repoID, alertNumber).First(&logicalAlert).Error
	require.NoError(t, err)

	stateTime := sqltime.Now()
	refBytes := []byte(ref)
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        repoID,
		LogicalAlertNumber:  alertNumber,
		State:               state,
		StateUpdatedAt:      stateTime,
		RefBytes:            refBytes,
		RuleSarifIdentifier: logicalAlert.SarifIdentifier,
		RequestedAt:         stateTime,
	}

	err = session.suggestedFixesService.DbService.CreateSuggestedFix(session.ctx, sfa)
	require.NoError(t, err)
}

func (session *Session) DisableTestFailuresForEnablementStatusExceptions() {
	session.ctx = appctx.WithReporter(session.ctx, exceptions.NullReporter)
}

func (session *Session) CreateRepository(t *testing.T, repoID ts.RepositoryEID, defaultRef []byte) {
	t.Helper()
	repo := &ts.Repository{
		RepositoryID:    repoID,
		DefaultRef:      defaultRef,
		SourceUpdatedAt: sqltime.Now(),
	}
	err := session.db.Save(repo).Error
	require.NoError(t, err)
}
