// Package cmd contains the code for the command-line interface
// portion of ghes-resource-migrator.
package cmd

// Execute executes the root command.
func Execute() error {
	return rootCmd.Execute()
}
