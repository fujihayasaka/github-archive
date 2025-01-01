package main

import (
	"context"
	"database/sql"

	throttler "github.com/github/go-freno-client"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/spf13/cobra"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/cmd/job-cli/healbuilds"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchcache"
)

type throttlerFunc func(bool) (throttler.Throttler, error)

func getRootCommand(
	ctx context.Context,
	obs *observability.Observability,
	conn *sql.DB,
	readOnlyConn *sql.DB,
	dbThrottlerFunc throttlerFunc,
	gcf github.Factory,
	repositoryClientFactory azp.RepositoryClientFactory,
	ghTwirpClient ghtwirp.Client,
	frenoClient freno.Client,
	cacheClient launchcache.HealingJobCache,
	dbBreaker *circuit.Breaker,
	dbROBreaker *circuit.Breaker,
	isMultiTenant bool,
) *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "bin/job-cli",
		Short: "Run a few different launch jobs",
	}

	var disableFrenoFlag bool
	rootCmd.PersistentFlags().BoolVar(&disableFrenoFlag, "disable-freno", false, "disable freno throttling")

	jobsCmd := &cobra.Command{
		Use:   "jobs",
		Short: "A variety of available jobs, pass in one of the subcommands",
	}

	hcc := &healbuilds.HealCommandClients{
		GithubClientFactory:  gcf,
		GhTwirpClient:        ghTwirpClient,
		ServiceClientFactory: repositoryClientFactory,
		FrenoClient:          frenoClient,
		CacheClient:          cacheClient,
	}

	jobsCmd.AddCommand(getPercentIncompleteCommand(ctx, obs))
	jobsCmd.AddCommand(getPercentRunCompletionDelayCommand(ctx, obs))
	jobsCmd.AddCommand(getPercentRunStartDelayCommand(ctx, obs))
	jobsCmd.AddCommand(getHealCommand(ctx, obs, conn, readOnlyConn, hcc, dbBreaker, dbROBreaker, isMultiTenant))
	jobsCmd.AddCommand(getExampleBackfillCommand(ctx, obs, conn, dbThrottlerFunc))
	jobsCmd.AddCommand(getAzpResourcesCreatedAtBackfillCommand(ctx, obs, conn, dbThrottlerFunc))
	jobsCmd.AddCommand(getAzpResourcesEntityIDBackfillCommand(ctx, obs, conn, dbThrottlerFunc))
	jobsCmd.AddCommand(getAzpResourcesTenantNameBackfillCommand(ctx, obs, conn, dbThrottlerFunc))
	jobsCmd.AddCommand(getAzpResourcesDeleteBlankRepoIdsCommand(ctx, obs, conn, dbThrottlerFunc))
	jobsCmd.AddCommand(getWorkflowSchedulesDeleteBlankActorIdsCommand(ctx, obs, conn, dbThrottlerFunc))

	rootCmd.AddCommand(
		jobsCmd,
	)

	return rootCmd
}
