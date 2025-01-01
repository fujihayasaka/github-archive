package percentruncompletiondelay

import (
	"context"
	"time"

	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	"github.com/github/go-kvp"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/utils/dsn"
)

type cfg struct {
	StatsPrefix   string `config:"launch,env=STATS_PREFIX,required"`
	StatsAddr     string `config:",env=STATS_ADDR,required"`
	DeployerDBURL string `config:",env=DEPLOYER_DATABASE_URL,required"`
}

type queryResult struct {
	ImpactedRepos int64
	TotalRepos    int64
}

const (
	Success = 0
	Failure = 1
	Timeout = time.Minute * 5
)

type Runner struct {
	// how often we produce this metric.
	intervalMinutes int64
	// how quickly a run has to be marked as completed after the actual completion of run on the actions service to not be considered delayed.
	thresholdMinutes int64
	obs              *observability.Observability
}

func New(intervalMinutes int64, obs *observability.Observability) Runner {

	thresholdMinutes := int64(thresholds.RunCompletionDelay / time.Minute)
	return Runner{
		intervalMinutes:  intervalMinutes,
		thresholdMinutes: thresholdMinutes,
		obs:              obs,
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

	now := time.Now().UTC()
	completedAtMin := now.Add(-time.Duration(r.intervalMinutes) * time.Minute)

	result, err := r.queryReposPercentage(ctx, cfg, completedAtMin)
	if err != nil {
		r.obs.Error(ctx, "Failed to query repo and run ratio", kvp.Err(err))
		return Failure
	}

	successfulRepos := result.TotalRepos - result.ImpactedRepos
	var ratio float64
	if result.TotalRepos != 0 {
		ratio = float64(successfulRepos) / float64(result.TotalRepos) * 100
	}

	// Publishing stats so we can determine if we're at 3 nines or better.
	r.obs.Gauge(ctx, "run_completion_delay_repos", statter.Tags{"impacted": "true"}, result.ImpactedRepos)
	r.obs.Gauge(ctx, "run_completion_delay_repos", statter.Tags{"impacted": "false"}, successfulRepos)
	r.obs.Log(ctx, "percent_run_completion_delay",
		kvp.Time("gh.launch.run_completed_at_minute", completedAtMin),
		kvp.Int64("gh.launch.impacted_repos.count", result.ImpactedRepos),
		kvp.Int64("gh.launch.total_repos.count", result.TotalRepos),
		kvp.Float("gh.launch.successful_repos_percentage", ratio),
		kvp.Int64("gh.launch.interval_minutes", r.intervalMinutes),
		kvp.Int64("gh.launch.threshold_minutes", r.thresholdMinutes),
	)

	return Success
}

func (r *Runner) queryReposPercentage(ctx context.Context, cfg *cfg, completedAtMin time.Time) (*queryResult, error) {
	conn, err := mysqldb.NewDB(r.obs.Statter, cfg.DeployerDBURL)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	query := `
		SELECT COUNT(DISTINCT(IF( 
			wbe.completed_at > wbe.azp_completed_at + INTERVAL ? MINUTE,
			wb.repository_id, NULL))) AS impactedRepos, 
		COUNT(DISTINCT(wb.repository_id)) AS totalRepos
		FROM workflow_build_executions wbe 
		INNER JOIN workflow_builds wb 
		ON wbe.workflow_build_id = wb.id 
		WHERE wbe.completed_at >= ?
		AND wbe.azp_completed_at IS NOT NULL;`

	row := conn.QueryRowContext(
		ctx,
		query,
		r.thresholdMinutes,
		completedAtMin)

	var result queryResult
	if err := row.Scan(&result.ImpactedRepos, &result.TotalRepos); err != nil {
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

func NewStatter(cfg *cfg) statter.Statter {
	statter := statter.New(&statter.Config{
		Prefix: cfg.StatsPrefix,
		Addr:   cfg.StatsAddr,
	})
	statter.Start()
	return statter
}
