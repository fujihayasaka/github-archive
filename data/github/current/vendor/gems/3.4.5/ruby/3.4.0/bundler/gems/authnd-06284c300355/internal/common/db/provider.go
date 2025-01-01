package db

import (
	stdErr "errors"
	"time"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

type Provider struct {
	dbs  map[string]*sqlx.DB
	done chan struct{}
}

func NewProvider(cfg *config.CommonConfig, schemas []string, logger log.Logger, statter stats.Client) (*Provider, error) {
	dbs := make(map[string]*sqlx.DB, len(schemas))
	for _, schema := range schemas {
		dbConfig, err := cfg.DatabaseConfigFor(schema)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to get db config for '%s' schema", schema)
		}

		sqlDB, err := Open(logger, dbConfig)
		if err != nil {
			return nil, err
		}

		dbs[schema] = sqlDB
	}

	provider := &Provider{
		dbs:  dbs,
		done: make(chan struct{}),
	}
	go provider.monitor(statter)
	return provider, nil
}

func (p *Provider) GetDB(schema string) (*sqlx.DB, error) {
	db, ok := p.dbs[schema]
	if !ok {
		return nil, errors.Errorf("no db found for '%s' schema", schema)
	}
	return db, nil
}

func (p *Provider) monitor(statter stats.Client) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			for name, db := range p.dbs {
				dbStatter := statter.WithTags(stats.Tags{"database": name})
				dbstats := db.Stats()
				dbStatter.Gauge("sql.idle", nil, int64(dbstats.Idle))
				dbStatter.Gauge("sql.in_use", nil, int64(dbstats.InUse))
				dbStatter.Gauge("sql.max_idle_closed", nil, dbstats.MaxIdleClosed)
				dbStatter.Gauge("sql.max_idle_time_closed", nil, dbstats.MaxIdleTimeClosed)
				dbStatter.Gauge("sql.max_lifetime_closed", nil, dbstats.MaxLifetimeClosed)
				dbStatter.Gauge("sql.max_open_connections", nil, int64(dbstats.MaxOpenConnections))
				dbStatter.Gauge("sql.open_connections", nil, int64(dbstats.OpenConnections))
				dbStatter.Gauge("sql.wait_count", nil, dbstats.WaitCount)
				dbStatter.Gauge("sql.wait_duration", nil, dbstats.WaitDuration.Nanoseconds())
			}
		case <-p.done:
			return
		}
	}
}

func (p *Provider) Close() error {
	close(p.done)

	var errs []error
	for schema, db := range p.dbs {
		if err := db.Close(); err != nil {
			errs = append(errs, errors.Wrapf(err, "failed to close db for '%s' schema", schema))
		}
	}
	return stdErr.Join(errs...)
}
