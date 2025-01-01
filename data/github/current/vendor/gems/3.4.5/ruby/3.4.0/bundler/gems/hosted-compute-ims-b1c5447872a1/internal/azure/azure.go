package azure

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure/clientbuilder"
	"github.com/github/hosted-compute-ims/internal/models"
)

type apiVersion string

const (
	apiVersionGalleryResources apiVersion = "2022-03-03"
	apiVersionLatestStable     apiVersion = "2022-09-01"
)

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_azure/mock_azure.go -package mocks_azure
type IAzureClient interface {
	// storage account methods
	CreateStorageAccountIfNotExists(ctx context.Context, storageKey *StorageKey, location string) error
	CreateStorageAccountContainerIfNotExists(ctx context.Context, storageKey *StorageContainerKey) error
	CopyImageToBlob(ctx context.Context, blobKey *StorageBlobKey, sourceUrl string, progressReporter func(update OperationProgressUpdate)) error
	CopyImageToBlobFastCopy(ctx context.Context, blobKey *StorageBlobKey, sourceUrl string, progressReporter func(update OperationProgressUpdate)) error
	// compute gallery methods
	CheckGalleryImageDefinitionExists(ctx context.Context, galleryImageDefinitionKey *GalleryImageDefinitionKey) (bool, error)
	CreateGalleryIfNotExists(ctx context.Context, galleryKey *GalleryKey, location string) error
	CreateGalleryImageDefinitionIfNotExists(ctx context.Context, galleryImageDefinitionKey *GalleryImageDefinitionKey, osType models.OsType, architecture models.Architecture, location string) error
	CreateImageVersionFromBlob(ctx context.Context, imageVersionKey *GalleryImageVersionKey, blob *StorageBlobKey, location string, replicationRegions ImageVersionReplications, progressReporter func(update OperationProgressUpdate)) error
	DeleteImageDefinition(ctx context.Context, imageDefinitionKey *GalleryImageDefinitionKey) error
	DeleteImageVersion(ctx context.Context, imageVersionKey *GalleryImageVersionKey) error
	DeleteBlob(ctx context.Context, blobKey *StorageBlobKey) error
	GetGalleryImageVersionSize(ctx context.Context, imageVersionKey *GalleryImageVersionKey) (int32, error)
	ListImageVersions(ctx context.Context, imageDefinitionKey *GalleryImageDefinitionKey, top int) ([]*armcompute.GalleryImageVersion, error)
	UpdateImageVersionReplications(ctx context.Context, imageVersionKey *GalleryImageVersionKey, replicationRegions ImageVersionReplications) error
	// resources methods
	CreateResourceGroupIfNotExists(ctx context.Context, rgKey *ResourceGroupKey, location string) error
}

type AzureClient struct {
	clientBuilder clientbuilder.ClientBuilder
	logger        *telemetry.ReportingLogger
}

func NewAzureClient(cfg *Config, logger *telemetry.ReportingLogger) (*AzureClient, error) {
	var credentials azcore.TokenCredential

	var err error

	if cfg.AzureClientID != "" && cfg.AzureTenantID != "" && cfg.AzureClientSecret != "" {
		credentials, err = azidentity.NewClientSecretCredential(cfg.AzureTenantID, cfg.AzureClientID, cfg.AzureClientSecret, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize client secret azure credentials: %w", err)
		}
	} else {
		// DefaultAzureCredential supports different auth methods and determines the appropriate credential type based off the environment variables
		// It fallbacks to Azure CLI auth session if no other methods are configured and works for local development from the box
		// https://github.com/Azure/azure-sdk-for-go/blob/main/sdk/azidentity/README.md#defaultazurecredential
		logger.Info("SPN credentials are not set, using default azure credentials")
		credentials, err = azidentity.NewDefaultAzureCredential(nil)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize default azure credentials: %w", err)
		}
	}

	return &AzureClient{
		clientBuilder: clientbuilder.NewClientBuilder(credentials, logger),
		logger:        logger,
	}, nil
}
