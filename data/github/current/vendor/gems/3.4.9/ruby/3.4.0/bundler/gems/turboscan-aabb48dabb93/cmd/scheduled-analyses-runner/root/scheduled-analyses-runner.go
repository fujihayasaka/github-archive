// Package root represents the command scheduled-analyses-runner which triggers the on:schedule runs for Default setup.
// See https://github.com/github/code-scanning/issues/7344 for context.
package root

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/app"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-stats"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts/botfetcher"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/hydro/publishers"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-scheduled-analyses-runner"

var ScheduledAnalysesRunnerCmd = &cobra.Command{
	Use:   "scheduled-analyses-runner",
	Short: "Command scheduled-analyses-runner triggers the on:schedule runs for Default setup",
	Long:  "Command scheduled-analyses-runner triggers the on:schedule runs for Default setup.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(jobName, realMain)
	},
}

func realMain(ctx context.Context, cfg *config.Config) error {
	if time.Now().UTC().Hour() < 3 && !cfg.IsEnterpriseEnv() {
		// Early exit if we are between (00-03 UTC) as we want to avoid submitting Actions runs
		appctx.Logger(ctx).Info("Exiting early as we cannot schedule Actions runs right now...")
		return nil
	}

	appctx.Logger(ctx).Info("scheduled-analyses-runner started.")
	start := time.Now()

	defer func() {
		appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": "scheduled-analyses-runner"}, time.Since(start))

		appctx.Logger(ctx).Info("scheduled-analyses-runner completed.")
	}()

	var cleaner app.Cleaner
	defer cleaner.Clean(ctx)

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return err
	}
	cleaner.Append(closeDB)

	launchClient, err := actions.New(cfg, actions.WithLogger(appctx.Logger(ctx)))
	if err != nil {
		return errors.Wrap(err, "failed to create launch client")
	}

	maClient, err := cfg.NewManagedAnalysesAPI(appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		return errors.Wrap(err, "failed to create managed analyses client")
	}

	repoService := repository.NewService(db)

	alertService, err := app.NewAlertService(db)
	if err != nil {
		return errors.Wrap(err, "failed to create alert service")
	}
	kc, err := cfg.NewKafkaConfig(appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		return errors.Wrap(err, "failed to create kafka config")
	}
	publisher, err := publishers.New(*kc, appctx.Stats(ctx))
	if err != nil {
		return errors.Wrap(err, "failed to create publisher")
	}

	dataService := managedanalysis.NewService(db, publisher)

	ma := &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: maClient,
		DataService:          dataService,
		LaunchApiClient:      launchClient,

		GetBotActor:          botfetcher.FromCfgOrAPI(cfg, maClient),
		DormantRepoDays:      cfg.DormanRepoDays(),
		EnabledStatusService: enabled_status.NewEnabledStatusService(db, alertService, repoService, dataService, publisher, true),
	}

	err = ma.RunOnSchedule(ctx, repoService)
	return errors.Wrap(err, "failed to run on schedule")
}
