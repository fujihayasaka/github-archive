package main

import (
	"log"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "turboscan",
	Short: "Main command to work with all sub services of Turboscan repository",
	Long:  "Main command to work with all sub services of Turboscan repository.",
	// This is an empty command - think of this as namespace for all commands
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		log.Fatal(err)
	}
}

func init() {
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	rootCmd.AddCommand(serviceCmd)
	rootCmd.AddCommand(cronjobsCmd)
}
