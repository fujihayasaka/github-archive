// Command s3-init creates the necessary S3 bucket
//
// This command is used in GHES and local development to set up minio correctly.
package main

import (
	"context"
	"os"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/sarif/store"
)

func main() {
	if err := realMain(false); err != nil {
		log.WithError(err).Error("Error while creating S3 bucket.")
		os.Exit(1)
	}
}

func realMain(dryRun bool) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "s3-init", func(ctx context.Context) error {
		created, err := store.CreateS3Bucket(cfg.AWSID, cfg.AWSSecret, cfg.AWSRegion, cfg.S3Bucket, cfg.S3Endpoint)
		if err != nil {
			return err
		}

		if created {
			appctx.Logger(ctx).Info("Created bucket.")
		} else {
			appctx.Logger(ctx).Info("Bucket already exists.")
		}

		return nil
	})
}
