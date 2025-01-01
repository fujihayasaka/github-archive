package main

import (
	"context"
	"database/sql"

	backoff "github.com/cenkalti/backoff/v4"
	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	"github.com/pkg/errors"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/dbmigrator"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"

	"github.com/github/launch/cmd/migratorctl/transitions/shared"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20200409104519"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220105000001"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220105000002"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220322142609"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220401225312"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220425220556"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220513175412"
	"github.com/github/launch/cmd/migratorctl/transitions/transition20220516161326"
)

type transition struct {
	version   uint
	migration dbmigrator.MigrationFunc
}

func getDeployerTransitions(db *sql.DB) (*dbmigrator.Transitioner, error) {
	transitioner := dbmigrator.NewTransitioner()

	if err := launchconfig.LoadGlobalConfig(); err != nil {
		return nil, errors.Wrap(err, "failed to load global config")
	}

	sharedConfig, err := loadSharedConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load shared transition config")
	}

	// In Codespaces environments (i.e. prebuilds), we need to skip any transitions that require
	// calls to external services. See https://github.com/github/c2c-actions-experience/issues/5983
	allowExternalCalls := !sharedConfig.IsCodespaces

	// For our hosted environment (github.com), we may choose to log known errors and continue,
	// revisiting problematic rows later to complete the transition. We can't do that for other
	// environments where a GitHub engineer won't attend to upgrade. Having an Enterprise transition
	// succeed despite errors will lead to downstream errors that are difficult to root cause.
	continueOnKnownError := !sharedConfig.IsEnterprise()

	wfbBackfillCfg, err := loadWfbBackfillConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load config for transition 20220322142609")
	}
	wfbeBackfillCfg, err := loadWfbeBackfillConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load config for transition 20220516161326")
	}

	wfsBackfillCfg, err := loadWfsBackfillConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load config for transition 20220401225312")
	}

	azprBackfillCfg, err := loadAzprBackfillConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load config for transition 20220425220556")
	}

	wfjBackfillCfg, err := loadWfjBackfillConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to load config for transition 20220513175412")
	}

	transitions := []transition{
		{20200409104519, transition20200409104519.GetTransition(db)},
		{20211223183435, transition20220105000001.GetTransition(db)},
		{20211227225903, transition20220105000002.GetTransition(db)},
		{20220322142609, transition20220322142609.GetTransition(wfbBackfillCfg, db, getDependencies(sharedConfig, "backfill_wfb_ids"), allowExternalCalls)},
		{20220401225312, transition20220401225312.GetTransition(wfsBackfillCfg, db, getDependencies(sharedConfig, "backfill_wfs_ids"), allowExternalCalls)},
		{20220425220556, transition20220425220556.GetTransition(azprBackfillCfg, db, getDependencies(sharedConfig, "backfill_azpr_ids"), allowExternalCalls, continueOnKnownError)},
		{20220513175412, transition20220513175412.GetTransition(wfjBackfillCfg, db, getDependencies(sharedConfig, "backfill_wfj_ids"), allowExternalCalls)},
		{20220516161326, transition20220516161326.GetTransition(wfbeBackfillCfg, db, getDependencies(sharedConfig, "backfill_wfbe_ids"), allowExternalCalls)},
	}

	for _, t := range transitions {
		err := transitioner.Add(t.version, t.migration)
		if err != nil {
			return nil, err
		}
	}

	return transitioner, nil
}

// nolint: unparam
func getPayloadsTransitions(_ *sql.DB) (*dbmigrator.Transitioner, error) {
	return dbmigrator.NewTransitioner(), nil
}

func loadSharedConfig() (*shared.TransitionCfg, error) {
	cfg := &shared.TransitionCfg{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadWfbBackfillConfig() (*transition20220322142609.Config, error) {
	cfg := &transition20220322142609.Config{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadWfsBackfillConfig() (*transition20220401225312.Config, error) {
	cfg := &transition20220401225312.Config{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadAzprBackfillConfig() (*transition20220425220556.Config, error) {
	cfg := &transition20220425220556.Config{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadWfjBackfillConfig() (*transition20220513175412.Config, error) {
	cfg := &transition20220513175412.Config{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func loadWfbeBackfillConfig() (*transition20220516161326.Config, error) {
	cfg := &transition20220516161326.Config{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func isLaunchCI(cfg *shared.TransitionCfg) bool {
	return cfg.LaunchCI == "1"
}

// Name needs to be unique across all transitions.
func getDependencies(cfg *shared.TransitionCfg, name string) shared.DependencyFunc {
	return func(rootCtx context.Context) (*shared.Dependencies, error) {
		obs, stop := cfg.GetObservability()

		dbThrottler := cfg.GetThrottler(freno.LaunchDBCluster)

		delay := backoff.NewExponentialBackOff()
		b := backoff.WithMaxRetries(delay, 5)

		var ghTwirpClient ghtwirp.Client
		var launchCache launchcache.Cache

		// In our CI environment, we don't have Redis and can't make external calls
		if !isLaunchCI(cfg) {
			breaker, err := abreaker.NewNamedRateBreaker(rootCtx, obs, abreaker.BuildRedisConfig(cfg.BreakerConfig), name)
			if err != nil {
				return nil, err
			}

			var doneCache func()
			launchCache, doneCache, err = cfg.GetCache(rootCtx, obs, breaker)
			if err != nil {
				return nil, err
			}
			defer doneCache()

			ghTwirpClient, err = cfg.SetupGitHubTwirpClient(rootCtx, obs, launchCache.GitHubTwirp(), name)
			if err != nil {
				return nil, err
			}
		}

		return &shared.Dependencies{
			Obs:           obs,
			StopObs:       stop,
			GhTwirpClient: ghTwirpClient,
			LaunchCache:   launchCache,
			DBThrottler:   dbThrottler,
			Backoff:       b,
		}, nil
	}
}
