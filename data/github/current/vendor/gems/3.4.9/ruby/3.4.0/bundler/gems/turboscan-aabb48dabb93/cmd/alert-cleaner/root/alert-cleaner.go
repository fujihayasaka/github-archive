// Package root is the entry point to the alert-cleaner command which is used to delete all the alerts for a specific repository.
// This is only meant to be called manually for support purposes (e.g. to unblock analyses for a repo that has reached the 1 million alert limit).
package root

import (
	"context"

	"github.com/spf13/cobra"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/pkg/errors"
)

type arguments struct {
	repoID ts.RepositoryEID
	delete bool
}

const (
	name             = "alert-cleaner"
	shortDescription = "is used to delete all existing alerts for a repository."
)

var AlertCleanerCmd = &cobra.Command{
	Use:   name,
	Short: shortDescription,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runCmd(cmd)
	},
}

func init() {
	AlertCleanerCmd.Flags().Uint64("repoID", 0, "Repository ID.")
	AlertCleanerCmd.Flags().Bool("delete", false, "When 'false' will only log the execution steps, without doing any deletions")
	err := AlertCleanerCmd.MarkFlagRequired("repoID")
	if err != nil {
		panic(err)
	}
}

func parseArgs(cmd *cobra.Command) (*arguments, error) {
	deleteFlag, err := cmd.Flags().GetBool("delete")
	if err != nil {
		return nil, err
	}
	repoID, err := cmd.Flags().GetUint64("repoID")
	if err != nil {
		return nil, err
	}
	return &arguments{
		delete: deleteFlag,
		repoID: ts.RepositoryEID(repoID),
	}, err
}

func runCmd(cmd *cobra.Command) error {
	args, err := parseArgs(cmd)
	if err != nil {
		return err
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "alert-cleaner", func(ctx context.Context) error {

		var cleanup app.Cleaner
		defer cleanup.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleanup.Append(closeDB)

		es, err := app.NewES(ctx, cfg)
		if err != nil {
			return errors.Wrap(err, "could not connect to ElasticSearch")
		}
		repoCleanupService := repository.NewRepositoryCleanupService(db, nil, es, nil)

		appctx.Logger(ctx).Info("Deleting Elasticsearch docs for the repo", args.repoID.AsKVP())
		if args.delete {
			err := repoCleanupService.ElasticSearchData(ctx, args.repoID)
			if err != nil {
				return err
			}
		} else {
			appctx.Logger(ctx).Info("Skipping deletion of Elasticsearch docs", args.repoID.AsKVP())
		}

		appctx.Logger(ctx).Info("Deleting alert data from MySQL", args.repoID.AsKVP())
		if args.delete {
			err := repoCleanupService.AlertData(ctx, args.repoID)
			if err != nil {
				return err
			}
		} else {
			appctx.Logger(ctx).Info("Skipping deletion of MySQL alerts", args.repoID.AsKVP())
		}
		return nil
	})
}
