package transition20200409104519

import (
	"context"
	"database/sql"
	"os"

	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	throttler "github.com/github/go-freno-client"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/dbmigrator"
	"github.com/github/launch/utils/asql"
)

type cfg struct {
	StatsPrefix   string `config:"launch,env=STATS_PREFIX"`
	StatsAddr     string `config:",env=STATS_ADDR"`
	ReportingAddr string `config:",env=HAYSTACK_URL"`
	FrenoAddr     string `config:",env=FRENO_ADDR"`
}

func GetTransition(db *sql.DB) dbmigrator.MigrationFunc {
	return func(ctx context.Context) error {
		cfg, err := loadConfig()
		if err != nil {
			return err
		}
		obs, stop := getObservability(cfg)
		defer stop()

		dbThrottler := getThrottler(cfg)

		var min, max sql.NullInt64
		row := db.QueryRow("SELECT min(id), max(id) FROM workflow_builds")
		err = row.Scan(&min, &max)
		if err != nil {
			return err
		}

		// If both min(id) and max(id) are null, just return nil.
		if !min.Valid && !max.Valid {
			return nil
		}

		it := asql.BatchIterator{
			Obs:         obs,
			DB:          db,
			DBThrottler: dbThrottler,

			BatchSize: 100,
			Start:     min.Int64,
			End:       max.Int64,
		}
		query := `UPDATE workflow_builds
		SET
		checkout_sha="",
		checkout_ref=""
		WHERE
		checkout_sha IS NULL
		AND checkout_ref IS NULL
		AND id >= {{.Min}}
		AND id <= {{.Max}}
		LIMIT 100`
		_, err = it.Run(ctx, query)
		return err
	}
}

func loadConfig() (*cfg, error) {
	cfg := &cfg{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}

func getLogger(cfg *cfg) logger.Logger {
	if cfg.ReportingAddr != "" {
		return logger.New(&logger.Config{
			Debug:     true,
			App:       "launch",
			ReportURL: cfg.ReportingAddr,
			Hostname:  getHostName(),
			// Report the following fields as tags to Sentry
			FieldTags: map[string]bool{
				"gh.repo.global_id": true,
				"gh.request_id":     true,
			},
		})
	}
	return logger.NullLogger()
}

func getHostName() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func getStatter(cfg *cfg) statter.Statter {
	if cfg.StatsAddr != "" {
		statter := statter.New(&statter.Config{
			Prefix: cfg.StatsPrefix,
			Addr:   cfg.StatsAddr,
		})
		statter.Start()
		return statter
	}
	return statter.NullStatter()
}

func getObservability(cfg *cfg) (*observability.Observability, func()) {
	log := getLogger(cfg)
	sttr := getStatter(cfg)
	defaultStatter := statter.DefaultStatter()
	return observability.New(log, sttr), func() {
		sttr.Stop()
		defaultStatter.Stop()
	}
}

func getThrottler(cfg *cfg) throttler.Throttler {
	if cfg.FrenoAddr != "" {
		return throttler.NewFrenoThrottler(cfg.FrenoAddr, "launch", "launch")
	}
	return throttler.DefaultThrottler
}
