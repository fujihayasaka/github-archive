// Package root provides the cmd for the conversion-observer
// that generates telemetry data for repos that have potentially
// converted from default setup.
package root

import (
	"context"
	"fmt"
	"time"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/hydro/publishers"

	"github.com/github/turboscan/ts/limits"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-conversion-observer"

var ConversionObserverCmd = &cobra.Command{
	Use:   "conversion-observer",
	Short: "Command conversion-observer observes conversions from default setup to advanced setup",
	Long:  "Command conversion-observer observes conversions from default setup to advanced setup.",
	RunE: func(cmd *cobra.Command, args []string) error {
		horizon, err := cmd.Flags().GetDuration("horizon")
		if err != nil {
			return err
		}

		return cronjob.Execute(jobName, func(ctx context.Context, cfg *config.Config) error {
			return realMain(ctx, cfg, horizon)
		})
	},
}

func realMain(ctx context.Context, cfg *config.Config, horizon time.Duration) error {
	appctx.Logger(ctx).Info("conversion-observer started.")
	start := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": "conversion-observer"}, time.Since(start))

		appctx.Logger(ctx).Info("conversion-observer completed.")
	}()

	ctx = appctx.With(ctx, kvp.String("gh.turboscan.conversion_observer.horizon", horizon.String()))

	var cleaner app.Cleaner
	defer cleaner.Clean(ctx)

	db, closeDB, err := app.NewDBWithReplica(ctx, cfg)
	if err != nil {
		return errors.Wrap(err, "failed to open DB")
	}
	cleaner.Append(closeDB)

	// we should use the db replica when available
	ctx = gormext.WithTryReplica(ctx, true)

	toolService := tool.NewService(db, limits.NewLimitSelector(cfg.Limits(), cfg.DisableSarifHardLimit))
	codeqlID, err := toolService.CodeQLToolID(ctx)
	if errors.Is(err, tool.ErrCodeQLNotInUse) {
		appctx.Logger(ctx).Info(err.Error())
		return nil
	}
	if err != nil {
		return errors.Wrap(err, "failed to get codeql tool id")
	}

	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return err
	}

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return err
	}

	maDataService := managedanalysis.NewService(db, publisher)
	alertService, err := app.NewAlertService(db)
	if err != nil {
		return errors.Wrap(err, "failed to create alert service")
	}
	repoService := repository.NewService(db)

	spokesC, err := spokes.NewClient(cfg.SpokesAddr, cfg.SpokesCert, cfg.SpokesClientKey, cfg.SpokesCaChain, appctx.Stats(ctx))
	if err != nil {
		return errors.Wrap(err, "failed to create spokes client")
	}
	fetchFile := managedanalyses.FetchFileWithCache(fetchFileWithSpokes(spokesC))

	co := managedanalyses.NewConversionObserver(maDataService.GetRepositoriesDisabledBetween, latestCodeqlYMLAnalyses(repoService, alertService, codeqlID), fetchFile)

	window := time.Minute * 30
	t1 := time.Now().Add(horizon * -1)
	t2 := t1.Add(window)
	err = co.ObserveConversionBetween(ctx, t1, t2)
	return errors.Wrap(err, "failed to observe conversions")
}

// fetchFileWithSpokes wraps the Spokes.GetFile method to satisfy the FetchFileFunc definition.
func fetchFileWithSpokes(c spokes.Spokes) managedanalyses.FetchFileFunc {
	return func(ctx context.Context, repoID ts.RepositoryEID, path string, sha ts.Sha) ([]byte, error) {
		out, err := c.GetFile(ctx, repoID, spokes.Filename(path), spokes.CommitOID(sha))
		if err != nil {
			return nil, err
		}
		if out == nil {
			return nil, errors.New("empty file or not found")
		}
		return out, nil
	}
}

func latestCodeqlYMLAnalyses(repoService *repository.Service, alertService *alert.Service, codeqlToolID ts.ToolID) func(context.Context, ts.RepositoryEID) ([]*ts.Analysis, error) {
	return func(ctx context.Context, repoID ts.RepositoryEID) ([]*ts.Analysis, error) {
		repo, err := repoService.Find(ctx, repoID)
		if err != nil {
			return nil, errors.Wrap(err, "failed to find repo")
		}
		if repo == nil {
			log.Error(fmt.Sprintf("repository %d not found", repoID))
			return nil, nil
		}

		ymlOrigin := ts.DeliveryOrigin_YML
		filter := ts.LatestAnalysisFilter{
			Ref:            repo.DefaultRef,
			ToolIDs:        []ts.ToolID{codeqlToolID},
			DeliveryOrigin: &ymlOrigin,
		}
		latestAnalyses, err := alertService.LatestAnalysesForRef(ctx, repoID, filter, true)
		if err != nil {
			return nil, errors.Wrap(err, "failed get latest analyses for ref")
		}

		return transforms.Map(latestAnalyses, func(la *ts.LatestAnalysis) *ts.Analysis { return &la.Analysis }), nil
	}
}

func init() {
	ConversionObserverCmd.Flags().Duration("horizon", time.Hour*24, "The time duration to look back for disabled repos. Defaults to 24h.")
}
