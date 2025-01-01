package cmd

import (
	"context"
	"fmt"

	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/spf13/cobra"
)

//nolint:gochecknoinits // inits are standard when using cobra.
func init() {
	var repositoryID int64
	var name, color, description string

	importRepoLabelCmd.Flags().Int64Var(&repositoryID, "repository_id", 0, "ID of the repository (required)")
	importRepoLabelCmd.Flags().StringVar(&name, "name", "", "Name of label (required)")
	importRepoLabelCmd.Flags().StringVar(&color, "color", "00ff00", "Color of label (optional)")
	importRepoLabelCmd.Flags().StringVar(&description, "description", "imported with importcli", "Description of label (optional)")

	importRepoLabelCmd.RunE = func(cmd *cobra.Command, args []string) error {
		resp, err := client.ImportLabels(context.Background(), &v1.ImportLabelsRequest{
			RepositoryId: repositoryID,
			Labels: []*v1.Label{
				{
					Name:        name,
					Color:       color,
					Description: description,
				},
			},
		})
		if err != nil {
			return fmt.Errorf("unable to import repository label: %w", err)
		}

		fmt.Printf("%+v\n", resp)
		return nil
	}

	rootCmd.AddCommand(importRepoLabelCmd)
}

var importRepoLabelCmd = &cobra.Command{
	Use:   "import-label",
	Short: "Adds label to a repository",
}
