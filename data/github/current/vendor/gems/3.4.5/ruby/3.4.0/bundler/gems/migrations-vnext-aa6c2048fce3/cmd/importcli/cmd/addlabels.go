package cmd

import (
	"context"
	"fmt"

	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/spf13/cobra"
)

//nolint:gochecknoinits // inits are standard when using cobra.
func init() {
	var repositoryID, issueNumber int64
	var labels []string

	addLabelsCmd.Flags().Int64Var(&repositoryID, "repository_id", 0, "ID of the repository (required)")
	addLabelsCmd.Flags().Int64Var(&issueNumber, "issue_number", 0, "Number of the issue (required)")
	addLabelsCmd.Flags().StringSliceVar(&labels, "labels", []string{}, "List of labels to apply, they must already exist on the repository (required)")

	addLabelsCmd.RunE = func(cmd *cobra.Command, args []string) error {
		resp, err := client.AddLabelsToIssue(context.Background(), &v1.AddLabelsToIssueRequest{
			RepositoryId: repositoryID,
			IssueNumber:  issueNumber,
			Labels:       labels,
		})
		if err != nil {
			return fmt.Errorf("unable to add labels to issue: %w", err)
		}

		fmt.Printf("%+v\n", resp)
		return nil
	}

	rootCmd.AddCommand(addLabelsCmd)
}

var addLabelsCmd = &cobra.Command{
	Use:   "add-labels-to-issue",
	Short: "Adds labels to an issue",
}
