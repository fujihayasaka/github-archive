// Package blob provides functionality and whatever abstractions are needed for accessing blob storage.
package blob

import (
	"bytes"
	"context"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
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

		spn := cfg.GetAzureSPN()
		spnConfigured := spn.Key != "" && spn.ClientID != "" && spn.TenantID != ""
		oidcConfigured := isOIDCConfigured()

		if oidcConfigured || spnConfigured {
			return createAuthenticatedAzureBlobClient(ctx, cfg, snapshotBlobsContainerName)
		}

		contextlogger.Info(ctx, "Neither OIDC nor SPN authentication is configured, so developer mode is assumed")
		return CreateDevelopmentAzureBlobClient(ctx, cfg.AzureStorageBlobEndpoint, snapshotBlobsContainerName)
	}

	// Because we're not globally enabled for snapshot blob storage yet, we don't consider this an error case
	return nil, nil
}

func createAuthenticatedAzureBlobClient(ctx context.Context, cfg *config.Config, container string) (BlobClient, error) {
	credential, err := getAzureCredential(ctx, cfg)
	if err != nil {
		return nil, err
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
		return nil, errors.Wrap(err, "couldn't create a new service client from credentials")
	}
	containerClient, err := getContainerEnsureExists(ctx, serviceClient, container)
	if err != nil {
		return nil, err
	}

	return &BlobClientFacade{containerClient}, nil
}

// getAzureCredential attempts to create Azure credentials using Workload Identity (OIDC) first,
// falling back to client secret authentication if:
//   - the OIDC environment variables are not present (e.g., dev mode, GHES), or
//   - OIDC credential creation fails, or
//   - a trial token acquisition against Azure AD fails (e.g., federated trust not yet configured).
//
// When running in a Moda pod with the azure.workload.identity/use label and an azure-access
// service account, the Azure Workload Identity webhook injects AZURE_CLIENT_ID, AZURE_TENANT_ID,
// and AZURE_FEDERATED_TOKEN_FILE into the pod environment. NewWorkloadIdentityCredential reads
// these automatically.
//
// azureStorageScope is the OAuth scope required by Azure Storage.
const azureStorageScope = "https://storage.azure.com/.default"

// oidcTokenTimeout is the maximum time to wait for the trial OIDC token
// acquisition during startup. Kept short so blob init can fail/fallback
// promptly under network issues.
const oidcTokenTimeout = 10 * time.Second

// TODO: remove client secret fallback once OIDC is verified in production across all stamps.
func getAzureCredential(ctx context.Context, cfg *config.Config) (azcore.TokenCredential, error) {
	// Only attempt OIDC when the Workload Identity webhook has injected all
	// required env vars. This avoids a confusing "not available" log in
	// intentional SPN-only configurations.
	var wiErr error
	if isOIDCConfigured() {
		wiCred, err := azidentity.NewWorkloadIdentityCredential(nil)
		if err != nil {
			wiErr = err
			contextlogger.Info(ctx, "Workload Identity credential creation failed, falling back to client secret",
				kvp.String("error", err.Error()))
		} else {
			// Validate OIDC can actually acquire a token — NewWorkloadIdentityCredential
			// only checks that env vars are present, not that the federated trust is
			// configured. Without this check, blob operations would fail at request
			// time with no fallback to client secret.
			tokenCtx, cancel := context.WithTimeout(ctx, oidcTokenTimeout)
			defer cancel()
			_, tokenErr := wiCred.GetToken(tokenCtx, policy.TokenRequestOptions{
				Scopes: []string{azureStorageScope},
			})
			if tokenErr == nil {
				contextlogger.Info(ctx, "using Azure Workload Identity (OIDC) authentication")
				return wiCred, nil
			}
			wiErr = tokenErr
			contextlogger.Info(ctx, "Workload Identity token acquisition failed, falling back to client secret",
				kvp.String("error", tokenErr.Error()))
		}
	}

	// Fall back to client secret authentication
	spn := cfg.GetAzureSPN()
	if spn.Key == "" || spn.ClientID == "" || spn.TenantID == "" {
		if wiErr != nil {
			return nil, fmt.Errorf("failed to find Azure credentials: Workload Identity failed (%w) and SPN client secret credentials not found in environment", wiErr)
		}
		return nil, fmt.Errorf("failed to find Azure credentials: Workload Identity not configured and SPN client secret credentials not found in environment")
	}

	secretCred, secretErr := azidentity.NewClientSecretCredential(spn.TenantID, spn.ClientID, spn.Key, &azidentity.ClientSecretCredentialOptions{})
	if secretErr != nil {
		return nil, errors.Wrap(secretErr, "couldn't create a client secret credential")
	}

	contextlogger.Info(ctx, "using Azure client secret authentication",
		kvp.String("gh.azure_blob_storage.spn_client_id", spn.ClientID),
		kvp.String("gh.azure_blob_storage.spn_tenant_id", spn.TenantID))
	return secretCred, nil
}

// isOIDCConfigured returns true when the Azure Workload Identity webhook has injected
// all required environment variables into the pod. All three must be present for
// NewWorkloadIdentityCredential to succeed.
func isOIDCConfigured() bool {
	return os.Getenv("AZURE_FEDERATED_TOKEN_FILE") != "" &&
		os.Getenv("AZURE_CLIENT_ID") != "" &&
		os.Getenv("AZURE_TENANT_ID") != ""
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
