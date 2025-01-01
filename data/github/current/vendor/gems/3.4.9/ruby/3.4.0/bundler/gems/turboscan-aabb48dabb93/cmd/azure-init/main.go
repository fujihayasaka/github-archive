package main

import (
	"context"
	"fmt"
	"os"
	"reflect"

	"github.com/github/turboscan/ts/appctx"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts/config"
)

const errorCodeContainerAlreadyExists = "ContainerAlreadyExists"

func main() {
	if err := realMain(); err != nil {
		log.WithError(err).Error("Error while creating Azure bucket.")
		os.Exit(1)
	}
}

/*
 * This makes a new Azure Storage Account and a new Storage Container so that
 * we can run the `SarifStore` Azure tests (usually only in CI).
 * The CI config makes use of
 * [Azurite](https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite?tabs=visual-studio),
 * a fake Azure, like we use Minio for the S3 storage tests.
 * Authenticating with Azure is complex: https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key#blob-queue-and-file-services-shared-key-authorization.
 */
func realMain() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "azure-init", func(ctx context.Context) error {
		logger := appctx.Logger(ctx)

		credential, err := azblob.NewSharedKeyCredential(cfg.AzureAccountName, cfg.AzureAccountKey)
		if err != nil {
			return err
		}

		client, err := azblob.NewClientWithSharedKeyCredential(cfg.AzureEndpoint+"/"+cfg.AzureAccountName, credential, nil)
		if err != nil {
			return err
		}

		_, err = client.CreateContainer(context.Background(), cfg.AzureContainer, nil)
		if err != nil {
			fmt.Printf("%+v\n", reflect.TypeOf(err))
			var responseError *azcore.ResponseError
			if ok := errors.As(err, &responseError); ok {
				if responseError.ErrorCode == errorCodeContainerAlreadyExists {
					logger.Info("Bucket already exists.")
					return nil
				}
			}
			return err
		}

		logger.Info("Created bucket.")

		return nil
	})
}
