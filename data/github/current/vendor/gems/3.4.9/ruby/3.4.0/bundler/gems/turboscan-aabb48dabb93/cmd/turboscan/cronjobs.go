package main

import (
	"github.com/spf13/cobra"

	codeqlgcCmd "github.com/github/turboscan/cmd/codeql-garbage-collector/root"
	metricsCmd "github.com/github/turboscan/cmd/codeql-secured-repos-metrics/root"
	co "github.com/github/turboscan/cmd/conversion-observer/root"
	emitCredentialExpirationCmd "github.com/github/turboscan/cmd/emit-credential-expiration/root"
	repoDel "github.com/github/turboscan/cmd/repo-deleter/root"
	repoIndexer "github.com/github/turboscan/cmd/repo-indexer/root"
	sar "github.com/github/turboscan/cmd/scheduled-analyses-runner/root"
	svrCmd "github.com/github/turboscan/cmd/stale-validation-runs/root"
)

var cronjobsCmd = &cobra.Command{
	Use:   "cronjobs",
	Short: "Subcommand to launch different cronjobs",
	Long:  "Subcommand to launch different cronjobs.",
}

var execCronjobCmd = &cobra.Command{
	Use:   "exec",
	Short: "Subcommand to execute cronjobs",
	Long:  "Subcommand to execute cronjobs.",
}

func init() {
	execCronjobCmd.AddCommand(svrCmd.StaleValidationRunsCmd)
	execCronjobCmd.AddCommand(sar.ScheduledAnalysesRunnerCmd)
	execCronjobCmd.AddCommand(co.ConversionObserverCmd)
	execCronjobCmd.AddCommand(repoDel.RepoDeleterMainCmd)
	execCronjobCmd.AddCommand(repoIndexer.RepoIndexerCmd)
	execCronjobCmd.AddCommand(metricsCmd.SecuredReposMetricsCMD)
	execCronjobCmd.AddCommand(codeqlgcCmd.CodeQLGarbageCollectorCmd)
	execCronjobCmd.AddCommand(emitCredentialExpirationCmd.EmitCredentialExpirationCmd)
	cronjobsCmd.AddCommand(execCronjobCmd)
}
