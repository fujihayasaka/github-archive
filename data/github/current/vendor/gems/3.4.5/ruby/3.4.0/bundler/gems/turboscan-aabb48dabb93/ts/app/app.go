// Package app provides an abstraction for an instrumented long-running Turboscan service.
// Each App must be assigned a server (defined by the Server interface) which is the process that
// is expected to serve the requests
package app

import (
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"os/signal"
	"slices"
	"syscall"

	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/sarif/store"

	"github.com/github/go-ctxutil"
	"github.com/github/turboscan/ts/mysql/archiver"
	sf "github.com/github/turboscan/ts/mysql/suggestedfixes"

	dbstats "github.com/github/go-stats/db"
	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts/botfetcher"
	"github.com/github/turboscan/ts/cocofix"

	"github.com/github/turboscan/ts/limits"

	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/hydro/publishers"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/workflows"

	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/repository"

	"github.com/jinzhu/gorm"
	_ "github.com/surma/stacksignal"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/sequence"
	"github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
)

// Server is the running process at the core of each Turboscan App
type Server interface {
	Start(ctx context.Context) error
	Stop(ctx context.Context) error
}

func RunServiceFunc(svcName string, svcFunc func(ctx context.Context, cfg *config.Config) (Server, CleanupFunc, error)) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	signalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	return appctx.WithContext(cfg, svcName, func(ctx context.Context) error {
		ctx = appctx.WithShutdown(ctx, signalCtx.Done())

		server, cleanup, serverErr := svcFunc(ctx, cfg)
		if serverErr != nil {
			return serverErr
		}

		defer cleanup(ctx)
		startErr := server.Start(ctx)
		// in most implementations of server Start actually blocks until the server has finished
		// this done check is unnecessary but makes sure if Start _is_ asynchronous it will run to
		// completion.
		<-ctx.Done()
		stopErr := server.Stop(ctxutil.DetachedCancel(ctx))
		runErr := stderrors.Join(startErr, stopErr)
		if !errors.Is(runErr, ctx.Err()) {
			return runErr
		}
		return nil
	})
}

func NewES(ctx context.Context, cfg *config.Config) (*elasticsearch.Service, error) {
	if cfg.ESAddr == "" {
		appctx.Logger(ctx).Info("no elasticsearch address configured, disabling search ...")
		return nil, nil
	}

	es, err := elasticsearch.NewService(ctx, cfg.ESUsername, cfg.ESPassword, cfg.ESAddr, cfg.IndexSettings())
	if err != nil {
		return nil, err
	}

	if cfg.ESSecondaryAddr != "" {
		if secondaryErr := es.SetSecondary(cfg.ESSecondaryUsername, cfg.ESSecondaryPassword, cfg.ESSecondaryAddr); secondaryErr != nil {
			errMessage := "failed setting up secondary ES"
			appctx.Logger(ctx).WithError(secondaryErr).Error(errMessage)
			appctx.Report(ctx, errors.Wrap(secondaryErr, errMessage), nil)
			// Continue as if the secondary ES is not set
		}
	}
	return es, nil
}

func NewManagedAnalysisService(ctx context.Context, cfg *config.Config, repoAPI ghgh.RepositoryAPI, rs *repository.Service, es *enabled_status.EnabledStatusService, ds *managedanalysis.Service, pub *publishers.HydroPublisher) (*maservice.ManagedAnalyses, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	ac, err := ghapi.New(cfg, logger, statter)
	if err != nil {
		return nil, err
	}

	launchClient, err := actions.New(cfg, actions.WithLogger(logger))
	if err != nil {
		logger.Info("failed to create launch client, disabling Actions integration ...")
	}

	maClient, err := cfg.NewManagedAnalysesAPI(logger, statter)
	if err != nil {
		return nil, err
	}

	workflowLibrary := workflows.NewLibrary(
		workflows.WithDefaultNonGHHostedRunnerLabel(cfg.ActionsDefaultNonGitHubHostedRunnerLabel()),
		workflows.WithForceNextVersion(cfg.IsEnterpriseEnv()),
		workflows.WithArtifactActionV3(cfg.IsEnterpriseEnv()),
		workflows.WithCustomRegistries(cfg.IsEnterpriseEnv()),
	)

	return &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: maClient,
		GitHubApiClient:      ac,
		DataService:          ds,
		LaunchApiClient:      launchClient,
		UpdateRepoMetadata:   managedanalyses.NewRepoMetaUpdater(rs, repoAPI),
		WorkflowsLibrary:     workflowLibrary,
		GetBotActor:          botfetcher.FromCfgOrAPI(cfg, maClient),
		Scheduler:            managedanalyses.NewScheduler(!cfg.IsEnterpriseEnv()),
		HydroPublisher:       pub,
		EnabledStatusService: es,
	}, nil
}

func NewSuggestedFixesService(ctx context.Context, cfg *config.Config, d *sf.Service, as *alert.Service, arch *archiver.Service, l *limits.LimitSelector, pub *publishers.HydroPublisher, aq *aqueduct.Client) (*suggestedfixes.SuggestedFixes, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	s, err := spokes.NewClient(cfg.SpokesAddr, cfg.SpokesCert, cfg.SpokesClientKey, cfg.SpokesCaChain, statter)
	if err != nil {
		return nil, err
	}

	cocofixThrottler, err := cocofix.NewThrottler(logger, cfg.CapiThrottlerUrl)
	if err != nil {
		return nil, err
	}

	sfClient, err := cfg.NewSuggestedFixesAPI(logger, statter)
	if err != nil {
		return nil, err
	}

	syncUpdate := func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		err := sfClient.SuggestedFixStateChanged(ctx, repoID, prID, alertNumbers)
		if err != nil {
			appctx.Report(ctx, errors.Wrap(err, "Failed to call internal Monolith Twirp service"), payload)
		}

		indexJob := &jobs.AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		}
		_, err = aq.PerformLater(ctx, indexJob)
		if err != nil {
			appctx.Report(ctx, errors.Wrap(err, "Failed to enqueue alert indexing job"), payload)
		}
	}

	capiConfig := cocofix.NewCapiConfig(cfg)
	return &suggestedfixes.SuggestedFixes{
		FixGenerator:                        cocofix.NewCocofixRunner(capiConfig, cocofixThrottler, cfg.IsProximaEnv(), pub),
		DbService:                           d,
		AlertService:                        as,
		ArchiveService:                      arch,
		SpokesClient:                        s,
		GitHubTwirpApiClient:                sfClient,
		LimitsSelector:                      l,
		SyncUpdate:                          syncUpdate,
		FixedAlertPublisher:                 pub,
		AutofixGeneratePublisher:            pub,
		DependabotAutofixResultPublisher:    pub,
		AutofixGenerationCompletedPublisher: pub,
	}, nil
}

func NewAlertService(db *gorm.DB) (*alert.Service, error) {
	seqCreator, err := sequence.NewMySQLSequenceCreator(db, ts.LogicalAlertsSeqTableName)
	if err != nil {
		return nil, err
	}
	return alert.NewService(db, seqCreator), nil
}

type Cleaner struct {
	cleanups []func() error
}

func (c *Cleaner) Clean(ctx context.Context) {
	var err error
	for _, fn := range slices.Backward(c.cleanups) {
		err = stderrors.Join(err, fn())
	}
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("error cleaning up")
	}
}

func (c *Cleaner) Append(f func() error) {
	c.cleanups = append(c.cleanups, f)
}

type CleanupFunc func(ctx context.Context)

func newDBStatter(ctx context.Context, db *gorm.DB) *gorm.DB {
	dbstatter := &dbstats.Reporter{
		Stats: appctx.Stats(ctx),
		DB:    gormext.GetDB(db),
	}
	go func() {
		if statterErr := dbstatter.Run(ctx); statterErr != nil {
			appctx.Logger(ctx).WithError(statterErr).Error("error running stats reporter")
		}
	}()
	return db
}

func NewDB(ctx context.Context, cfg *config.Config) (*gorm.DB, func() error, error) {
	db, err := config.OpenDB(&config.DBOptions{Config: cfg}, appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		appctx.Report(ctx, err, nil)
		return nil, nil, err
	}
	return newDBStatter(ctx, db), db.Close, err
}

func NewDBWithReplica(ctx context.Context, cfg *config.Config) (*gorm.DB, func() error, error) {
	db, err := config.DBWithReplicaConnection(&config.DBOptions{Config: cfg}, appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		return nil, nil, err
	}
	return newDBStatter(ctx, db), db.Close, err
}

func NewSarifStore(ctx context.Context, cfg *config.Config) (store.SarifStore, func() error, error) {
	s := store.NewSarifStore(cfg.GetStorageEngine(), cfg)
	if err := s.Open(ctx); err != nil {
		return nil, nil, err
	}
	cleanup := func() error {
		return s.Close(ctxutil.DetachedCancel(ctx))
	}
	return s, cleanup, nil
}
