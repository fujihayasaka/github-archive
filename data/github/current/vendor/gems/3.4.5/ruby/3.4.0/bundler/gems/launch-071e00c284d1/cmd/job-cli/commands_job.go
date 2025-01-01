package main

import (
	"context"
	"database/sql"
	"time"

	circuit "github.com/rubyist/circuitbreaker"
	"github.com/spf13/cobra"

	"github.com/github/go-kvp"

	"github.com/facebookgo/clock"

	"github.com/github/launch/cmd/job-cli/databasebackfills"
	"github.com/github/launch/cmd/job-cli/healbuilds"
	"github.com/github/launch/cmd/job-cli/percentincompleteworkflows"
	"github.com/github/launch/cmd/job-cli/percentruncompletiondelay"
	"github.com/github/launch/cmd/job-cli/percentrunstartdelay"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/asql"
)

func getPercentIncompleteCommand(ctx context.Context, obs *observability.Observability) *cobra.Command {
	var pctCmdInterval int64
	pctCmd := &cobra.Command{
		Use:   "percentIncompleteWorkflows",
		Short: "Log statistics of the percent of incomplete workflows during the last [interval] hours",
		Run: func(cmd *cobra.Command, args []string) {
			r := percentincompleteworkflows.New(pctCmdInterval, obs)
			r.Run(ctx)
		},
	}
	pctCmd.Flags().Int64VarP(&pctCmdInterval, "interval", "i", 1, "MySQL Interval to check, in hours")
	return pctCmd
}

func getPercentRunStartDelayCommand(ctx context.Context, obs *observability.Observability) *cobra.Command {
	var interval int64
	pctCmd := &cobra.Command{
		Use:   "percentRunStartDelay",
		Short: "Log statistics of the percent of repos with workflow runs starting within [threshold] minutes over [interval] minutes",
		Run: func(cmd *cobra.Command, args []string) {
			r := percentrunstartdelay.New(interval, obs)
			r.Run(ctx)
		},
	}
	pctCmd.Flags().Int64VarP(&interval, "interval", "i", 1, "Interval to check, in minutes")
	return pctCmd
}

func getPercentRunCompletionDelayCommand(ctx context.Context, obs *observability.Observability) *cobra.Command {
	var interval int64
	pctCmd := &cobra.Command{
		Use:   "percentRunCompletionDelay",
		Short: "Log statistics of the percent of repos with workflow runs completing within [threshold] minutes after actual run completion over [interval] minutes",
		Run: func(cmd *cobra.Command, args []string) {
			r := percentruncompletiondelay.New(interval, obs)
			r.Run(ctx)
		},
	}
	pctCmd.Flags().Int64VarP(&interval, "interval", "i", 1, "Interval to check, in minutes")
	return pctCmd
}

func getHealCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, readOnlyConn *sql.DB, hcc *healbuilds.HealCommandClients, breaker *circuit.Breaker, breakerRO *circuit.Breaker, isMultiTenant bool) *cobra.Command {
	var healCmdFrom, healCmdTo, healCmdPBGracePeriod time.Duration
	healCmd := &cobra.Command{
		Use:   "healWorkflows",
		Short: "Attempt to heal 'stuck' workflows that are not completed yet overdue",
		Run: func(cmd *cobra.Command, args []string) {
			adb := asql.New(conn, obs, obs, breaker, asql.LaunchCluster)
			globalIDMigrator := deployer.NewGlobalIDMigrator(hcc.GhTwirpClient)
			executionsRepo := deployer.NewWorkflowBuildExecutionsRepository(adb, obs, clock.New(), globalIDMigrator)
			wfbRepo := deployer.NewWorkflowBuildsRepository(
				adb, obs.Logger, obs.Statter, clock.New(), nil, executionsRepo, globalIDMigrator, isMultiTenant)

			adbReadOnly := asql.New(readOnlyConn, obs, obs, breakerRO, asql.LaunchROCluster)
			wfbRepoRO := deployer.NewWorkflowBuildsRepositoryReadOnly(
				adbReadOnly, obs.Logger, obs.Statter, clock.New(), globalIDMigrator, isMultiTenant)
			r := healbuilds.New(healCmdFrom, healCmdTo, healCmdPBGracePeriod, obs, wfbRepo, wfbRepoRO, hcc)
			r.Run(ctx)
		},
	}
	healCmd.Flags().DurationVarP(&healCmdFrom, "from", "f", healbuilds.DefaultMaxHealableJobAge, "Max number of hours since workflow queueing to heal from")
	healCmd.Flags().DurationVarP(&healCmdTo, "to", "t", healbuilds.DefaultMinHealableJobAge, "Min number of hours since workflow queueing to heal from")
	healCmd.Flags().DurationVarP(&healCmdPBGracePeriod, "postback", "p", healbuilds.DefaultPostbackGracePeriod, "Grace period for status postbacks to be processed after a run has completed")
	return healCmd
}

func getAzpResourcesCreatedAtBackfillCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool

	backfillCmd := &cobra.Command{
		Use:   "backfillAzpResourcesCreatedAt",
		Short: "Backfill `created_at` in `azp_resources` table",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}

			r := databasebackfills.New(obs, conn, t)
			return r.RunAzpResourcesBackfill(ctx, "created_at", "locked_at")
		},
	}

	backfillCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return backfillCmd
}

func getAzpResourcesEntityIDBackfillCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool

	backfillCmd := &cobra.Command{
		Use:   "backfillAzpResourcesEntityId",
		Short: "Backfill `entity_id` in `azp_resources` table",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}

			r := databasebackfills.New(obs, conn, t)
			return r.RunAzpResourcesBackfill(ctx, "entity_id", "repository_id")
		},
	}

	backfillCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return backfillCmd
}

func getAzpResourcesTenantNameBackfillCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool

	backfillCmd := &cobra.Command{
		Use:   "backfillAzpResourcesTenantName",
		Short: "Backfill `tenant_name` in `azp_resources` table",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}

			r := databasebackfills.New(obs, conn, t)
			return r.RunAzpResourcesBackfill(ctx, "tenant_name", "organization_name")
		},
	}

	backfillCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return backfillCmd
}

func getWorkflowSchedulesDeleteBlankActorIdsCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool

	deleteCmd := &cobra.Command{
		Use:   "deleteWorkflowSchedulesWithoutActor",
		Short: "Delete workflow schedules without an actor",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}

			r := databasebackfills.New(obs, conn, t)
			return r.RunDeleteWorkflowSchedulesWithoutActor(ctx)
		},
	}

	deleteCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return deleteCmd
}

func getAzpResourcesDeleteBlankRepoIdsCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool

	backfillCmd := &cobra.Command{
		Use:   "deleteAzpResourcesBlankRepositoryIds",
		Short: "Deletes rows with blank `repository_id` values in `azp_resources` table",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}

			r := databasebackfills.New(obs, conn, t)
			return r.RunAzpResourcesDeleteBlank(ctx, "repository_id")
		},
	}

	backfillCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return backfillCmd
}

func getExampleBackfillCommand(ctx context.Context, obs *observability.Observability, conn *sql.DB, dbThrottlerFunc throttlerFunc) *cobra.Command {
	var disableFrenoFlag bool
	exampleBackfillCmd := &cobra.Command{
		Use:   "exampleBackfillProgram", // cobra docs recommend camelCase for command names
		Short: "Example program for backfilling a database column using Freno",
		RunE: func(cmd *cobra.Command, args []string) error {
			t, err := dbThrottlerFunc(disableFrenoFlag)
			if err != nil {
				obs.Error(ctx, "error creating throttler", kvp.Err(err))
				return err
			}
			r := databasebackfills.New(obs, conn, t)
			return r.RunBackfillWorkflowBuildsCreatedAt(ctx)
		},
	}

	exampleBackfillCmd.Flags().BoolVar(&disableFrenoFlag, "disable-freno", false, "Disable Freno throttling")
	return exampleBackfillCmd
}
