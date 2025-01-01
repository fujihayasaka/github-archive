package main

import (
	cleaner "github.com/github/turboscan/cmd/alert-cleaner/root"
	migrator "github.com/github/turboscan/cmd/migratorctl/root"

	"github.com/spf13/cobra"
)

var utilCmd = &cobra.Command{
	Use:   "util",
	Short: "Utilities for TurboScan",
	Long:  `Utilities for TurboScan`,
}

func init() {
	utilCmd.AddCommand(migrator.MigratorCTLCmd)
	utilCmd.AddCommand(cleaner.AlertCleanerCmd)
	rootCmd.AddCommand(utilCmd)
}
