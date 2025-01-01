// Package root powers the ghapi command which provides a small utility to test various API calls.
package root

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/ghapi"
	gogh "github.com/google/go-github/v52/github"
)

var GHApiCmd = &cobra.Command{
	Use:   "ghapi",
	Short: "Utility command that fetches the annotations of a workflow run",
	Long:  "Utility command that fetches the annotations of a workflow run.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return realMain(cmd)
	},
}

type Args struct {
	repoID uint64
	wrID   uint64
	token  string
}

func parseArgs(cmd *cobra.Command) (*Args, error) {
	var args Args
	var err error
	args.repoID, err = cmd.Flags().GetUint64("repo")
	if err != nil {
		return nil, errors.Wrap(err, "failed to get repo flag")
	}
	args.wrID, err = cmd.Flags().GetUint64("wr")
	if err != nil {
		return nil, errors.Wrap(err, "failed to get wr flag")
	}

	// Get GITHUB_TOKEN from env
	args.token = os.Getenv("GITHUB_TOKEN")

	if args.repoID == 0 {
		return nil, errors.New("missing required flag: -repo")
	}
	if args.wrID == 0 {
		return nil, errors.New("missing required flag: -wr")
	}
	return &args, nil
}

func realMain(cmd *cobra.Command) error {
	args, err := parseArgs(cmd)
	if err != nil {
		return err
	}

	ctx := context.Background()
	var c *gogh.Client
	if args.token != "" {
		c = gogh.NewTokenClient(ctx, args.token)
	} else {
		c = gogh.NewClient(&http.Client{})
	}
	data, err := ghapi.GetWorkflowRunAnnotations(ctx, c, ts.RepositoryEID(args.repoID), ts.WorkflowRunEID(args.wrID))
	if err != nil {
		return err
	}

	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	fmt.Printf("%+v\n", string(b))
	return nil
}

func init() {
	GHApiCmd.Flags().Uint64("repo", 0, "repository id")
	GHApiCmd.Flags().Uint64("wr", 0, "workflow run id")
}
