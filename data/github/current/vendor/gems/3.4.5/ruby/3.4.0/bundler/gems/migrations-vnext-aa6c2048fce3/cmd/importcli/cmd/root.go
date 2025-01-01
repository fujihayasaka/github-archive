// Package cmd contains subcommands of the importcli.
package cmd

import (
	"fmt"
	"net/http"

	twirpClient "github.com/github/migrations-vnext/internal/pkg/client"

	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/spf13/cobra"
)

var (
	client  *twirpClient.ImportClient
	baseURL string
)

var rootCmd = &cobra.Command{
	Use:   "twirpcli",
	Short: "twirpcli is a CLI for interacting with the octoshift twirp APIs",
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		httpClient, err := twirpAuth.NewRequestHMACSigner("octoshifthmac", &http.Client{})
		if err != nil {
			return fmt.Errorf("unable to create hmac signer: %w", err)
		}
		client = twirpClient.NewImportClient(baseURL, httpClient)
		return nil
	},
}

//nolint:gochecknoinits // inits are standard when using cobra.
func init() {
	// Add the persistent baseURL flag, which will be available to all subcommands
	rootCmd.PersistentFlags().StringVar(&baseURL, "base-url", "http://api.github.localhost/internal", "Base URL for the twirp API")
}

// Execute the command.
func Execute() error {
	return rootCmd.Execute()
}
