// Package blob provides functionality and whatever abstractions are needed for accessing blob storage.
package blob

import (
	"bytes"
	"context"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/streaming"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
)

type BlobClient interface {
	// CreateBlob creates a blob and uploads contents to it. It returns a URL, which is expected to be
	// used to fetch the blob back out again. The client will assign a unique ID, but use the parentDirectory
	// as a prefix, allowing callers to organize blobs.
	CreateBlob(ctx context.Context, parentDirectory string, contents []byte) (blobURL string, err error)
	// GetBlob gets a blob by the blobURL, loading it fully into memory and returning a byte slice.
	GetBlob(ctx context.Context, blobURL string) (contents []byte, err error)
}

type BlobClientFacade struct {
	containerClient *azblob.ContainerClient
}

func InitializeSnapshotsBlobClientIfEnabled(ctx context.Context, cfg *config.Config) (client BlobClient, err error) {
	// Should match what is in terraform configuration
	snapshotBlobsContainerName := "snapshot-blobs"
	return initializeBlobClientIfEnabled(context.Background(), cfg, snapshotBlobsContainerName)
}

func initializeBlobClientIfEnabled(ctx context.Context, cfg *config.Config, snapshotBlobsContainerName string) (client BlobClient, err error) {
	if !cfg.Enterprise {
		contextlogger.Info(ctx, "AzureStorageForSnapshotsEnabled is enabled, starting blob storage init")
		if cfg.GetAzureSPN().Key != "" && cfg.GetAzureSPN().ClientID != "" && cfg.GetAzureSPN().TenantID != "" {
			contextlogger.Info(ctx, "SPN authentication is configured, connecting to a production blob instance",
				kvp.String("gh.azure_blob_storage.spn_client_id", cfg.GetAzureSPN().ClientID),
				kvp.String("gh.azure_blob_storage.spn_tenant_id", cfg.GetAzureSPN().TenantID))
			return createAuthenticatedAzureBlobClient(ctx, cfg, snapshotBlobsContainerName)
		} else {
			contextlogger.Info(ctx, "SPN authentication is not configured, so developer mode is assumed")
			return CreateDevelopmentAzureBlobClient(ctx, cfg.AzureStorageBlobEndpoint, snapshotBlobsContainerName)
		}
	}

	// Because we're not globally enabled for snapshot blob storage yet, we don't consider this an error case
	return nil, nil
}

func createAuthenticatedAzureBlobClient(ctx context.Context, cfg *config.Config, container string) (BlobClient, error) {
	credential, err := azidentity.NewClientSecretCredential(cfg.GetAzureSPN().TenantID, cfg.GetAzureSPN().ClientID, cfg.GetAzureSPN().Key, &azidentity.ClientSecretCredentialOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "couldn't create a client secret credential")
	}
	serviceClient, err := azblob.NewServiceClient(cfg.AzureStorageBlobEndpoint, credential, &azblob.ClientOptions{
		Retry: policy.RetryOptions{
			MaxRetries: 2,
			// Ideally, we would have the timeout scale somehow with the size of the blob we're uploading.
			// Unfortunately that's not possible with this library now, so this sets what should be a very long timeout.
			TryTimeout: time.Second * 2,
		},
	})
	if err != nil {
		return nil, errors.Wrap(err, "couldn't create a new service client from client credentials")
	}
	containerClient, err := getContainerEnsureExists(ctx, serviceClient, container)
	if err != nil {
		return nil, err
	}

	return &BlobClientFacade{containerClient}, nil
}

func CreateDevelopmentAzureBlobClient(ctx context.Context, azureStorageBlobEndpoint string, container string) (BlobClient, error) {
	connectionString := fmt.Sprintf("DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=%v;", azureStorageBlobEndpoint)
	serviceClient, err := azblob.NewServiceClientFromConnectionString(connectionString, nil)
	if err != nil {
		return nil, errors.Wrap(err, "couldn't create a new service client from connection string")
	}
	containerClient, err := getContainerEnsureExists(ctx, serviceClient, container)
	if err != nil {
		return nil, err
	}

	return &BlobClientFacade{containerClient}, nil
}

func (b *BlobClientFacade) CreateBlob(ctx context.Context, parentDirectory string, contents []byte) (blobURL string, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "BlobStorageTracer", "CreateBlob",
		kvp.Int("snapshot.blob_size", len(contents)),
	)
	defer ender()

	// Callers want to "categorize" (e.g. have a hierarchy) for the blobs, but we aren't guaranteed to have a fully unique name.
	// So, we assume hierarchical delimiters (this could be a bad assumption, but by default this is "/") and create a unique id ourselves.
	uniqueID := uuid.New()
	containerRelativePath := fmt.Sprintf("%v/%v", parentDirectory, uniqueID)

	blobClient, err := b.containerClient.NewBlockBlobClient(containerRelativePath)
	if err != nil {
		return "", errors.Wrap(err, "blob client creation failed")
	}

	reader := bytes.NewReader(contents)
	_, err = blobClient.Upload(ctx, streaming.NopCloser(reader), &azblob.BlockBlobUploadOptions{})
	if err != nil {
		return "", errors.Wrap(err, "blob upload failed")
	}

	return blobClient.URL(), nil
}

func (b *BlobClientFacade) GetBlob(ctx context.Context, blobURLString string) (contents []byte, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "BlobStorageTracer", "GetBlob")
	defer ender()

	var blobName string
	blobURL, err := url.Parse(blobURLString)
	if err != nil {
		return nil, errors.Wrap(err, "the blob URL could not be parsed when trying to GetBlob")
	}

	containerURL, err := url.Parse(b.containerClient.URL())
	if err != nil {
		return nil, errors.Wrap(err, "the container URL could not be parsed when trying to GetBlob")
	}

	blobName = strings.TrimPrefix(blobURL.Path, containerURL.Path+"/")

	// if we made it down this far, blobName is initialized
	blobClient, err := b.containerClient.NewBlockBlobClient(blobName)
	if err != nil {
		return nil, errors.Wrap(err, "blob client creation failed")
	}

	response, err := blobClient.Download(ctx, &azblob.BlobDownloadOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "blob download failed")
	}

	readCloser := response.Body(&azblob.RetryReaderOptions{})
	downloadedData := &bytes.Buffer{}
	_, err = downloadedData.ReadFrom(readCloser)
	if err != nil {
		return nil, errors.Wrap(err, "blob download failed while filling buffer")
	}

	return downloadedData.Bytes(), nil
}

func getContainerEnsureExists(ctx context.Context, serviceClient *azblob.ServiceClient, containerName string) (*azblob.ContainerClient, error) {
	container, err := serviceClient.NewContainerClient(containerName)
	if err != nil {
		return nil, err
	}

	_, err = container.Create(ctx, &azblob.ContainerCreateOptions{})
	if err != nil && !strings.Contains(err.Error(), "ContainerAlreadyExists") {
		return nil, err
	}

	return container, nil
}
