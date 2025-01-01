// Command scheduled-analyses-runner triggers the on:schedule runs for Default setup.
// See https://github.com/github/code-scanning/issues/7344 for context.
package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/scheduled-analyses-runner/root"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "scheduled-analyses-runner",
	Short: "Command scheduled-analyses-runner triggers the on:schedule runs for Default setup",
	Long:  "Command scheduled-analyses-runner triggers the on:schedule runs for Default setup.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return root.ScheduledAnalysesRunnerCmd.Execute()
	},
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run service")
		os.Exit(1)
	}
}
