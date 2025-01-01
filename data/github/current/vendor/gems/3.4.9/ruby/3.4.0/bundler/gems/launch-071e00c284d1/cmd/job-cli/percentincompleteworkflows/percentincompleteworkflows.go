package percentincompleteworkflows

import (
	"context"
	"time"

	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	"github.com/github/go-kvp"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/dsn"
)

type cfg struct {
	StatsPrefix   string `config:"launch,env=STATS_PREFIX,required"`
	StatsAddr     string `config:",env=STATS_ADDR,required"`
	DeployerDBURL string `config:",env=DEPLOYER_DATABASE_URL,required"`
}

type queryResult struct {
	Total    int64
	Complete int64
}

const (
	Success = 0
	Failure = 1
	Timeout = time.Minute * 5
)

type Runner struct {
	interval int64
	obs      *observability.Observability
}

func New(interval int64, obs *observability.Observability) Runner {
	return Runner{
		interval: interval,
		obs:      obs,
	}
}

func (r *Runner) Run(ctx context.Context) int {
	ctx, cancel := context.WithTimeout(ctx, Timeout)
	defer cancel()

	cfg, err := NewConfig()
	if err != nil {
		r.obs.Error(ctx, "Failed to load configuration", kvp.Err(err))
		return Failure
	}

	cfg.DeployerDBURL, err = dsn.WithInterpolateParams(cfg.DeployerDBURL, "true")
	if err != nil {
		r.obs.Error(ctx, "unable to set interpolateParams attribute", kvp.Err(err))
		return Failure
	}

	result, err := r.queryRatioComplete(ctx, cfg)
	if err != nil {
		r.obs.Error(ctx, "Failed to query completion ratio", kvp.Err(err))
		return Failure
	}

	var ratio float64
	if result.Total != 0 {
		ratio = float64(result.Complete) / float64(result.Total) * 100
	}

	r.obs.Gauge(ctx, "percent_completed_workflows", statter.Tags{}, int64(ratio))
	r.obs.Log(ctx, "percent_completed_workflows",
		kvp.Int64("gh.launch.completed_runs.count", result.Complete),
		kvp.Int64("gh.launch.total_runs.count", result.Total),
		kvp.Float("gh.launch.completed_runs_percentage", ratio),
		kvp.Int64("gh.launch.interval_hours", r.interval),
	)

	return Success
}

func (r *Runner) queryRatioComplete(ctx context.Context, cfg *cfg) (*queryResult, error) {
	conn, err := mysqldb.NewDB(r.obs.Statter, cfg.DeployerDBURL)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	query := `
		SELECT COUNT(*) AS total,
		COALESCE(SUM(IF(completed_at IS NOT NULL, 1, 0)), 0) AS complete
		FROM workflow_build_executions
		WHERE queued_at > ? - INTERVAL ? HOUR
	`

	row := conn.QueryRowContext(ctx, query, time.Now(), r.interval)

	var result queryResult
	if err := row.Scan(&result.Total, &result.Complete); err != nil {
		return nil, err
	}
	return &result, nil
}

func NewConfig() (*cfg, error) {
	cfg := &cfg{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}
	return cfg, nil
}
