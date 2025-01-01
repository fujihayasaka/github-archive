package main

import (
	"github.com/spf13/cobra"

	alertlinkcmd "github.com/github/turboscan/cmd/alertlinkprocessorsvc/root"
	atcmd "github.com/github/turboscan/cmd/analysistriggersvc/root"
	aqcmd "github.com/github/turboscan/cmd/aqueductsvc/root"
	cqltelcmd "github.com/github/turboscan/cmd/codeqltelemetryprocessorsvc/root"
	expectedcodeqlruncmd "github.com/github/turboscan/cmd/expectedcodeqlrunprocessorsvc/root"
	hycmd "github.com/github/turboscan/cmd/hydrosvc/root"
	repocmd "github.com/github/turboscan/cmd/reposvc/root"
	tscmd "github.com/github/turboscan/cmd/turboscansvc/root"
	workflowcmd "github.com/github/turboscan/cmd/workflowsvc/root"
)

var serviceCmd = &cobra.Command{
	Use:   "service",
	Short: "Subcommand to launch different services such as TurboscanSVC or HydroSVC",
	Long:  "Subcommand to launch different services such as TurboscanSVC or HydroSVC.",
}

var startServiceCmd = &cobra.Command{
	Use:   "start",
	Short: "Subcommand to start services",
	Long:  "Subcommand to start services.",
}

func init() {
	startServiceCmd.AddCommand(
		tscmd.TurboscanSvcCmd,
		hycmd.HydroSvcCmd,
		alertlinkcmd.AlertLinkCmd,
		atcmd.AnalysisTriggerCmd,
		aqcmd.AqueductCmd,
		cqltelcmd.CodeQLTelemetryProcessorsCmd,
		workflowcmd.WorkflowSvcCmd,
		repocmd.RepoSvcCmd,
		expectedcodeqlruncmd.ExpectedCodeqlRunProcessorCmd,
	)
	serviceCmd.AddCommand(startServiceCmd)
}
