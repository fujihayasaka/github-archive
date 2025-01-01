package blob

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blockblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/export"
	"github.com/github/github-telemetry-go/log"
	"github.com/google/uuid"
)

var blobClient *azblob.Client

func SetupBlobClient(cfg config.StorageAccountConfig) error {
	serviceUrl := fmt.Sprintf("https://%s.blob.core.windows.net/", cfg.AccountName)
	var cred azcore.TokenCredential
	var err error

	if cfg.IsDev && len(cfg.ClientSecret) == 0 {
		log.Warn("Using Azure CLI credential for development environment.")
		cred, err = azidentity.NewAzureCLICredential(nil)
	} else {
		cred, err = azidentity.NewClientSecretCredential(cfg.TenantId, cfg.ClientId, cfg.ClientSecret, nil) // CI, lab or prod
	}
	if err != nil {
		return fmt.Errorf("failed to create Azure credential: %w", err)
	}

	blobClient, err = azblob.NewClient(serviceUrl, cred, nil)
	if err != nil {
		return fmt.Errorf("failed to create blob client: %w", err)
	}

	return nil
}

// TestBlobClient tests the blob client by uploading a test blob.
func TestBlobClient(ctx context.Context) error {
	blobName := fmt.Sprintf("test/%s.txt", uuid.New().String())
	client := GetBlockBlobClient(GetContainerClient(export.ExportStatusContainerName), blobName)
	_, err := client.UploadBuffer(ctx, []byte("test"), nil)
	if err != nil {
		return fmt.Errorf("failed to test blob client: %w", err)
	}
	return nil
}

func BlobClient() *azblob.Client {
	return blobClient
}

func GetBlockBlobClient(containerClient *container.Client, blobName string) *blockblob.Client {
	return containerClient.NewBlockBlobClient(blobName)
}

func GetContainerClient(containerName string) *container.Client {
	return blobClient.ServiceClient().NewContainerClient(containerName)
}
