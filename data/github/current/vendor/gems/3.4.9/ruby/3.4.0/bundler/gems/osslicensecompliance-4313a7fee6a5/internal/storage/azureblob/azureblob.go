// Package azureblob provides Azure Blob Storage integration for the OSS License Compliance service.
// It handles creation and management of Azure storage containers and blob buckets.
package azureblob

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	"github.com/github/osslicensecompliance/internal/config"
	"gocloud.dev/blob"
	"gocloud.dev/blob/azureblob"
)

// AzureContainer represents the different types of Azure storage containers used by the application.
type AzureContainer uint

const (
	// UnknownContainer represents an unknown or invalid container type.
	UnknownContainer AzureContainer = iota
	// RepositoryContainer is used for storing repository-level policies.
	RepositoryContainer
	// OrganizationContainer is used for storing organization-level policies.
	OrganizationContainer
	// EnterpriseContainer is used for storing enterprise-level policies.
	EnterpriseContainer
)

var containerNames = map[AzureContainer]string{
	RepositoryContainer:   "repository-policies",
	OrganizationContainer: "organization-policies",
	EnterpriseContainer:   "enterprise-policies",
}

// When a container is ready for use, it should be added to this list so
// we initialise a storage client for it on startup up.
var activeContainers = []AzureContainer{
	RepositoryContainer,
	OrganizationContainer,
	EnterpriseContainer,
}

func (c AzureContainer) String() string {
	if name, exists := containerNames[c]; exists {
		return name
	}
	return "unknown"
}

// AzureBucketContainers provides typed access to specific container buckets
type AzureBucketContainers struct {
	buckets BlobBuckets
}

// RepositoryBucket returns the repository policies bucket
func (abc *AzureBucketContainers) RepositoryBucket() *blob.Bucket {
	b, ok := abc.buckets[RepositoryContainer]
	if !ok {
		return nil
	}
	return b
}

// OrganizationBucket returns the organization policies bucket
func (abc *AzureBucketContainers) OrganizationBucket() *blob.Bucket {
	b, ok := abc.buckets[OrganizationContainer]
	if !ok {
		return nil
	}
	return b
}

// EnterpriseBucket returns the enterprise policies bucket
func (abc *AzureBucketContainers) EnterpriseBucket() *blob.Bucket {
	b, ok := abc.buckets[EnterpriseContainer]
	if !ok {
		return nil
	}
	return b
}

// BlobBuckets are the Azure buckets per container
type BlobBuckets map[AzureContainer]*blob.Bucket

// NewBlobBuckets creates a new AzureBucketContainers instance with all required storage buckets
// configured based on the provided configuration. It supports both development and live modes.
func NewBlobBuckets(ctx context.Context, cfg *config.Config) (*AzureBucketContainers, error) {
	var buckets BlobBuckets
	var err error

	if cfg.Mode != "live" {
		buckets, err = newDevBuckets(ctx, cfg)
	} else {
		buckets, err = newAuthenticatedBuckets(ctx, cfg)
	}

	if err != nil {
		return nil, err
	}

	return &AzureBucketContainers{buckets: buckets}, nil
}

func newDevBuckets(ctx context.Context, cfg *config.Config) (BlobBuckets, error) {
	if cfg.AzureBlobEndpoint == "" {
		return nil, errors.New("AzureBlobEndpoint must be non-empty")
	}
	connectionString := fmt.Sprintf("DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=%s;", cfg.AzureBlobEndpoint)

	buckets := BlobBuckets{}
	for _, azContainer := range activeContainers {
		containerClient, err := container.NewClientFromConnectionString(connectionString, azContainer.String(), &container.ClientOptions{})
		if err != nil {
			return nil, fmt.Errorf("failed to create Azure container client: %w", err)
		}

		// In development mode, we should unobtrusively create any containers that do not exist.
		_, err = containerClient.Create(ctx, nil)
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && !bloberror.HasCode(responseErr, bloberror.ContainerAlreadyExists) {
			return nil, fmt.Errorf("failed to create Azure container %s: %w", azContainer.String(), err)
		}

		bucket, err := azureblob.OpenBucket(ctx, containerClient, &azureblob.Options{})
		if err != nil {
			return nil, fmt.Errorf("failed to open Azure blob bucket: %w", err)
		}

		buckets[azContainer] = bucket
	}

	return buckets, nil
}

func newAuthenticatedBuckets(ctx context.Context, cfg *config.Config) (BlobBuckets, error) {
	// Validate required configuration
	if cfg.AzureStorageAccount == "" {
		return nil, errors.New("AzureStorageAccount must be non-empty (check AZURE_STORAGE_ACCOUNT environment variable)")
	}

	// Default retry policy explicitly specified for clarity
	clientOptions := azcore.ClientOptions{
		Retry: policy.RetryOptions{
			MaxRetries: 3,
			RetryDelay: 4 * time.Second,
		},
	}

	spnCreds, found := cfg.GetAzureStorageCreds()
	if !found {
		return nil, errors.New("failed to find one or more Azure SPN credentials in environment")
	}

	credOpts := &azidentity.ClientSecretCredentialOptions{
		ClientOptions: clientOptions,
	}
	cred, err := azidentity.NewClientSecretCredential(spnCreds.TenantID, spnCreds.ClientID, spnCreds.ClientSecret, credOpts)
	if err != nil {
		return nil, fmt.Errorf("failed to create Azure client secret credentials: %w", err)
	}

	accountURL := fmt.Sprintf("https://%s.blob.core.windows.net/", cfg.AzureStorageAccount)
	containerOpts := &container.ClientOptions{
		ClientOptions: clientOptions,
	}

	buckets := BlobBuckets{}
	for _, azContainer := range activeContainers {
		containerURL := fmt.Sprintf("%s%s", accountURL, azContainer.String())
		containerClient, err := container.NewClient(containerURL, cred, containerOpts)
		if err != nil {
			return nil, fmt.Errorf("failed to create Azure container: %w", err)
		}

		bucket, err := azureblob.OpenBucket(ctx, containerClient, &azureblob.Options{})
		if err != nil {
			return nil, fmt.Errorf("failed to open Azure blob bucket: %w", err)
		}

		buckets[azContainer] = bucket
	}

	return buckets, nil
}
