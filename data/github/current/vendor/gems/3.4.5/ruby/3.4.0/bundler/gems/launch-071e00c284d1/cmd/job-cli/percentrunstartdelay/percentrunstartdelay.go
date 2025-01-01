package percentrunstartdelay

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	"github.com/github/go-kvp"
	"golang.org/x/sync/errgroup"

	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/flow/flowfile"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/dsn"
	"github.com/github/launch/workflowbuild/build"
)

type cfg struct {
	StatsPrefix   string `config:"launch,env=STATS_PREFIX,required"`
	StatsAddr     string `config:",env=STATS_ADDR,required"`
	DeployerDBURL string `config:",env=DEPLOYER_DATABASE_URL,required"`
}

type queryResult struct {
	ImpactedRepos int64
	TotalRepos    int64
	DelayedRuns   int64
	TotalRuns     int64
	Backend       types.WorkflowBackend
	Environment   string
}

type dynamicQueryResult struct {
	queryResult
	WorkflowFilePath string
}

type labelledQueryResult struct {
	queryResult
	CustomerLabel string
}

const (
	Success = 0
	Failure = 1
	Timeout = time.Minute * 5
)

type Runner struct {
	// how often we produce this metric.
	intervalMinutes int64
	// how quickly a run has to start to not be considered delayed.
	thresholdMinutes int64
	obs              *observability.Observability
}

func New(intervalMinutes int64, obs *observability.Observability) Runner {

	thresholdMinutes := int64(thresholds.RunStartDelay / time.Minute)
	return Runner{
		intervalMinutes:  intervalMinutes,
		thresholdMinutes: thresholdMinutes,
		obs:              obs,
	}
}

func (r *Runner) Run(ctx context.Context) int {
	ctx, cancel := context.WithTimeout(ctx, Timeout)
	g, ctx := errgroup.WithContext(ctx)
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
	createdAtMax := now.Add(-time.Duration(r.thresholdMinutes) * time.Minute)
	createdAtMin := createdAtMax.Add(-time.Duration(r.intervalMinutes) * time.Minute)

	conn, err := mysqldb.NewDB(r.obs.Statter, cfg.DeployerDBURL)
	if err != nil {
		r.obs.Error(ctx, "unable to connect to db", kvp.Err(err))
		return Failure
	}
	defer conn.Close()

	g.Go(func() error {
		results, err := r.queryReposPercentageWithLabels(ctx, createdAtMin, createdAtMax, conn)
		if err != nil {
			r.obs.Error(ctx, "Failed to query repo and run ratio", kvp.Err(err))
			return err
		}

		for _, result := range results {
			customerLabel := result.CustomerLabel
			if customerLabel == "" {
				customerLabel = customerlabels.NoneLabel
			}

			successfulRepos := result.TotalRepos - result.ImpactedRepos
			var ratio float64
			if result.TotalRepos != 0 {
				ratio = float64(successfulRepos) / float64(result.TotalRepos) * 100
			}

			successfulRuns := result.TotalRuns - result.DelayedRuns
			var runRatio float64
			if result.TotalRuns != 0 {
				runRatio = float64(successfulRuns) / float64(result.TotalRuns) * 100
			}

			// Publishing two separate stats so we can determine if we're at 3 nines or better.
			// Also this gives up the option to chart the absolute numbers.
			baseTags := statter.Tags{"customer_label": customerLabel, "backend": result.Backend.String(), "environment": result.Environment}
			impactedTags := baseTags.Merge(statter.Tags{"impacted": "true"})
			successfulTags := baseTags.Merge(statter.Tags{"impacted": "false"})

			r.obs.Gauge(ctx, "run_start_delay_repos", impactedTags, result.ImpactedRepos)
			r.obs.Gauge(ctx, "run_start_delay_repos", successfulTags, successfulRepos)
			r.obs.Gauge(ctx, "run_start_delay_runs", impactedTags, result.DelayedRuns)
			r.obs.Gauge(ctx, "run_start_delay_runs", successfulTags, successfulRuns)
			r.obs.Counter(ctx, "run_start_delay_run_count", impactedTags, result.DelayedRuns)
			r.obs.Counter(ctx, "run_start_delay_run_count", successfulTags, successfulRuns)
			r.obs.Log(ctx, "percent_run_start_delay",
				kvp.String("gh.launch.customer_label", customerLabel),
				kvp.Time("gh.launch.run_created_at_min", createdAtMin),
				kvp.Time("gh.launch.run_created_at_max", createdAtMax),
				kvp.Int64("gh.launch.impacted_repos.count", result.ImpactedRepos),
				kvp.Int64("gh.launch.total_repos.count", result.TotalRepos),
				kvp.Int64("gh.launch.delayed_runs.count", result.DelayedRuns),
				kvp.Int64("gh.launch.total_runs.count", result.TotalRuns),
				kvp.String("gh.launch.backend", result.Backend.String()),
				kvp.Float("gh.launch.successful_repos_percentage", ratio),
				kvp.Float("gh.launch.successful_runs_percentage", runRatio),
				kvp.Int64("gh.launch.interval_minutes", r.intervalMinutes),
				kvp.Int64("gh.launch.threshold_minutes", r.thresholdMinutes),
			)
		}
		return nil
	})

	g.Go(func() error {
		results, err := r.queryReposPercentageForDynamicEvents(ctx, createdAtMin, createdAtMax, conn)
		if err != nil {
			r.obs.Error(ctx, "Failed to query repo and run ratio for dynamic run", kvp.Err(err))
			return err
		}

		for _, result := range results {
			integrator, _, ok := flowevents.ExtractDynamicWorkflowFilePath(result.WorkflowFilePath)
			if !ok {
				if result.WorkflowFilePath != "BuildFailed" {
					return fmt.Errorf("could not extract workflow file path: %s", result.WorkflowFilePath)
				}
				integrator = "buildfailed"
			}
			successfulRepos := result.TotalRepos - result.ImpactedRepos
			var ratio float64
			if result.TotalRepos != 0 {
				ratio = float64(successfulRepos) / float64(result.TotalRepos) * 100
			}

			successfulRuns := result.TotalRuns - result.DelayedRuns
			var runRatio float64
			if result.TotalRuns != 0 {
				runRatio = float64(successfulRuns) / float64(result.TotalRuns) * 100
			}

			impactedTags := statter.Tags{"impacted": "true", "dynamic_run_integrator": integrator, "backend": result.Backend.String()}
			successfulTags := statter.Tags{"impacted": "false", "dynamic_run_integrator": integrator, "backend": result.Backend.String()}
			r.obs.Gauge(ctx, "run_start_delay_repos_dynamic", impactedTags, result.ImpactedRepos)
			r.obs.Gauge(ctx, "run_start_delay_repos_dynamic", successfulTags, successfulRepos)
			r.obs.Gauge(ctx, "run_start_delay_runs_dynamic", impactedTags, result.DelayedRuns)
			r.obs.Gauge(ctx, "run_start_delay_runs_dynamic", successfulTags, successfulRuns)
			r.obs.Log(ctx, "percent_run_start_delay_dynamic",
				kvp.String("gh.launch.dynamic_run_integrator", integrator),
				kvp.Time("gh.launch.run_created_at_min", createdAtMin),
				kvp.Time("gh.launch.run_created_at_max", createdAtMax),
				kvp.Int64("gh.launch.impacted_repos.count", result.ImpactedRepos),
				kvp.Int64("gh.launch.total_repos.count", result.TotalRepos),
				kvp.Int64("gh.launch.delayed_runs.count", result.DelayedRuns),
				kvp.Int64("gh.launch.total_runs.count", result.TotalRuns),
				kvp.String("gh.launch.backend", result.Backend.String()),
				kvp.Float("gh.launch.successful_repos_percentage", ratio),
				kvp.Float("gh.launch.successful_runs_percentage", runRatio),
				kvp.Int64("gh.launch.interval_minutes", r.intervalMinutes),
				kvp.Int64("gh.launch.threshold_minutes", r.thresholdMinutes),
			)
		}
		return nil
	})

	if err := g.Wait(); err != nil {
		r.obs.Error(ctx, "One or more run start query failed", kvp.Err(err))
		return Failure
	}

	return Success
}

func (r *Runner) queryReposPercentageWithLabels(ctx context.Context, createdAtMin time.Time, createdAtMax time.Time, conn *sql.DB) ([]*labelledQueryResult, error) {

	// * Ignore reruns.
	// * Ignore runs intentionally delayed.
	// * Ignore scheduled runs.
	query := `
		SELECT b.backend,
		CASE
			WHEN b.workflow_file_path LIKE CONCAT(?, '/%') THEN 'production'
			WHEN b.workflow_file_path LIKE CONCAT(?, '/%') THEN 'production'
			WHEN b.workflow_file_path LIKE CONCAT(?, '/%') THEN 'lab'
			ELSE 'inconclusive'
		END as environment,
		COALESCE(b.reporting_metadata ->> '$.customer_label', '') as customer_label,
		COUNT(DISTINCT(IF(
			x.state < ? OR COALESCE(x.started_at, x.completed_at) > b.event_time + INTERVAL ? MINUTE,
			b.repository_id, NULL))) AS impactedRepos,
		COUNT(IF(
			x.state < ? OR COALESCE(x.started_at, x.completed_at) > b.event_time + INTERVAL ? MINUTE,
		1, NULL)) AS delayedRuns,
		COUNT(DISTINCT(b.repository_id)) AS totalRepos,
		COUNT(*) AS totalRuns
		FROM workflow_build_executions AS x
		JOIN workflow_builds AS b
			ON b.id = x.workflow_build_id
		WHERE x.created_at >= ? AND x.created_at < ?
		-- scheduled runs have a lower priority and we haven't established a delay threshold for them.
		AND b.event != 'schedule'
		-- the original event time is irrelevant for reruns.
		AND b.rerun = false
		-- ignore runs where the delay was self-imposed, like hitting concurrency limits or offline self-hosted runners.
		AND x.was_delayed = false
		GROUP BY b.backend, customer_label, environment`

	rows, err := conn.QueryContext(
		ctx,
		query,
		flowfile.ProdPipelinesDirectory,
		flowevents.DynamicWorkflowFilePath,
		flowfile.LabPipelinesDirectory,
		build.WorkflowStateStarted,
		r.thresholdMinutes,
		build.WorkflowStateStarted,
		r.thresholdMinutes,
		createdAtMin,
		createdAtMax)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	var results []*labelledQueryResult
	for rows.Next() {
		var result labelledQueryResult
		if err := rows.Scan(&result.Backend, &result.Environment, &result.CustomerLabel, &result.ImpactedRepos, &result.DelayedRuns, &result.TotalRepos, &result.TotalRuns); err != nil {
			return nil, err
		}
		results = append(results, &result)
	}

	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return results, nil
}

func (r *Runner) queryReposPercentageForDynamicEvents(ctx context.Context, createdAtMin time.Time, createdAtMax time.Time, conn *sql.DB) ([]*dynamicQueryResult, error) {

	// * Ignore reruns.
	// * Ignore runs intentionally delayed.
	// * Include only dynamic events
	query := `
		SELECT b.backend,
		b.workflow_file_path as integration_by_slug,
		COUNT(DISTINCT(IF(
			x.state < ? OR COALESCE(x.started_at, x.completed_at) > b.event_time + INTERVAL ? MINUTE,
			b.repository_id, NULL))) AS impactedRepos,
		COUNT(IF(
			x.state < ? OR COALESCE(x.started_at, x.completed_at) > b.event_time + INTERVAL ? MINUTE,
		1, NULL)) AS delayedRuns,
		COUNT(DISTINCT(b.repository_id)) AS totalRepos,
		COUNT(*) AS totalRuns
		FROM workflow_build_executions AS x
		JOIN workflow_builds AS b
			ON b.id = x.workflow_build_id
		WHERE x.created_at >= ? AND x.created_at < ?
		AND b.event = 'dynamic' -- only interested in dynamic events
		-- the original event time is irrelevant for reruns.
		AND b.rerun = false
		-- ignore runs where the delay was self-imposed, like hitting concurrency limits or offline self-hosted runners.
		AND x.was_delayed = false
		GROUP BY b.backend, integration_by_slug`
	rows, err := conn.QueryContext(
		ctx,
		query,
		build.WorkflowStateStarted,
		r.thresholdMinutes,
		build.WorkflowStateStarted,
		r.thresholdMinutes,
		createdAtMin,
		createdAtMax)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	var results []*dynamicQueryResult
	for rows.Next() {
		var result dynamicQueryResult
		if err := rows.Scan(&result.Backend, &result.WorkflowFilePath, &result.ImpactedRepos, &result.DelayedRuns, &result.TotalRepos, &result.TotalRuns); err != nil {
			return nil, err
		}
		results = append(results, &result)
	}

	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return results, nil
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
