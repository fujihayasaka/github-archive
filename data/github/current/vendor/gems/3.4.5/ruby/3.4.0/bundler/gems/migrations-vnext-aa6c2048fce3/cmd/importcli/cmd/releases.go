package cmd

import (
	"context"
	"fmt"
	"time"

	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/spf13/cobra"
	"google.golang.org/protobuf/types/known/timestamppb"
)

//nolint:gochecknoinits // inits are standard when using cobra.
func init() {
	var repositoryID int64
	var state int32
	var authorLogin, releaseName, tag, body, targetCommitish string
	var preRelease bool

	createReleaseCmd.Flags().Int64Var(&repositoryID, "repository_id", 0, "ID of the repository (required)")
	createReleaseCmd.Flags().Int32Var(&state, "state", 1, "1: Published, 2: Draft (required)")
	createReleaseCmd.Flags().StringVar(&authorLogin, "author_login", "", "Author login of release creator (required)")
	createReleaseCmd.Flags().StringVar(&releaseName, "release_name", "", "Name/title of the release (required)")
	createReleaseCmd.Flags().StringVar(&tag, "tag", "", "Tag of the release (required)")
	createReleaseCmd.Flags().StringVar(&body, "body", "", "Body of the release (required)")
	createReleaseCmd.Flags().StringVar(&targetCommitish, "commitish", "", "Target commitish of the release (default:'')")
	createReleaseCmd.Flags().BoolVar(&preRelease, "prerelease", false, "is pre release (default: false)")

	createReleaseCmd.RunE = func(cmd *cobra.Command, args []string) error {
		resp, err := client.ImportRelease(context.Background(), &v1.ImportReleaseRequest{
			RepositoryId:    repositoryID,
			AuthorLogin:     authorLogin,
			Name:            releaseName,
			TagName:         tag,
			Body:            body,
			State:           v1.ReleaseState(state),
			PendingTag:      "", // This appears to be ignored in the octoshift API.
			IsPreRelease:    preRelease,
			TargetCommitish: targetCommitish,
			CreatedAt:       timestamppb.New(time.Now()),
		})
		if err != nil {
			return fmt.Errorf("unable to create release: %w", err)
		}

		fmt.Printf("%+v\n", resp)
		return nil
	}

	rootCmd.AddCommand(createReleaseCmd)
}

var createReleaseCmd = &cobra.Command{
	Use:   "create-release",
	Short: "Create a release",
}
