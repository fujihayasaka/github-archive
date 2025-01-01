package azure

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/pageblob"
)

const (
	copyImageToBlobTimeout         = 5 * time.Hour
	copyImageToBlobPollingInterval = 10 * time.Second
	createStorageAccountTimeout    = 1 * time.Minute
	createStorageAccountInterval   = 1 * time.Second
)

const (
	fastCopy_PageSize                   int64  = 4 * 1024 * 1024 // 4MB
	fastCopy_ThreadsPerGroup            int64  = 64
	fastCopy_GroupSize                  int64  = fastCopy_PageSize * fastCopy_ThreadsPerGroup // 4MB * 64 = 256MB
	fastCopy_CheckpointFrequency        int64  = 5 * 1024 * 1024 * 1024                       // 5GB
	fastCopy_CheckpointFullyCopiedValue int64  = 1 * 1024 * 1024 * 1024 * 1024                // 1TB
	fastCopy_CheckpointMetadataKey      string = "Imscopyprogress"
	fastCopy_CopyAttemptsCountInThread  int    = 5
)

func (c *AzureClient) CopyImageToBlob(ctx context.Context, blobKey *StorageBlobKey, sourceUrl string, progressReporter func(update OperationProgressUpdate)) error {
	client, err := c.clientBuilder.PageBlobClient(blobKey.SubscriptionId, blobKey.BlobUrl())
	if err != nil {
		return fmt.Errorf("failed to initialize azure blobs client: %w", err)
	}

	operationCtx, cancelFunc := context.WithTimeout(ctx, copyImageToBlobTimeout)
	defer cancelFunc()

	isRunning, err := isBlobAlreadyCopying(operationCtx, client)
	if err != nil {
		return fmt.Errorf("failed to check if blob already copying: %w", err)
	}

	// if blob is already copying, we don't need to start copy operation. So just start polling for status
	if !isRunning {
		_, err = client.StartCopyFromURL(operationCtx, sourceUrl, nil)
		if err != nil {
			return fmt.Errorf("failed to copy file from url to blob: %w", err)
		}
	}

	for {
		select {
		case <-operationCtx.Done():
			return fmt.Errorf("copying file from url to blob failed: %w", operationCtx.Err())
		default:
			resp, err := client.GetProperties(operationCtx, nil)
			if err != nil {
				return fmt.Errorf("failed to poll blob copy status: %w", err)
			}

			if resp.CopyStatus != nil && *resp.CopyStatus != blob.CopyStatusTypePending {
				if *resp.CopyStatus == blob.CopyStatusTypeSuccess {
					return nil
				}

				return fmt.Errorf("copying file from url to blob failed with status '%s'. Details: %s", *resp.CopyStatus, *resp.CopyStatusDescription)
			}

			progressReporter(blobPropertiesToOperationProgressUpdate(&resp))
		}

		time.Sleep(copyImageToBlobPollingInterval)
	}
}

func (c *AzureClient) CopyImageToBlobFastCopy(ctx context.Context, blobKey *StorageBlobKey, sourceUrl string, progressReporter func(update OperationProgressUpdate)) error {
	// this function implements fast copy approach for Azure Blob Storage, the approach is similar to how AzCopy works under hood (https://github.com/Azure/azure-storage-azcopy)
	// it copies file in 4MB chunks by calling UploadPagesFromURL for every chunk.
	// source file is split into chunk groups (4MB * 64 threadsPerGroup = 256MB) and chunks of the same group are copied in parallel
	// since fast copy approach is sync (unlike "StartCopyFromURL" azure function which is async),
	// we save copying progress every 5GB to blob metadata and continue from last known checkpoint in case of failure
	// rate limits for Storage REST API are equal to Storage Account Throughput: https://learn.microsoft.com/en-us/azure/storage/common/scalability-targets-standard-account
	ctx, cancelFunc := context.WithTimeout(ctx, copyImageToBlobTimeout)
	defer cancelFunc()

	sourceBlobSize, err := getSourceVhdBlobSize(ctx, sourceUrl)
	if err != nil {
		return err
	}

	dstBlobClient, err := c.clientBuilder.PageBlobClient(blobKey.SubscriptionId, blobKey.BlobUrl())
	if err != nil {
		return fmt.Errorf("failed to initialize page blob client for destination blob: %w", err)
	}

	if err = ensureDestinationPageBlobIsCreated(ctx, dstBlobClient, sourceBlobSize); err != nil {
		return fmt.Errorf("failed to ensure page blob is created: %w", err)
	}

	lastCheckpoint, err := getCopyProgressFromBlobMetadata(ctx, dstBlobClient)
	if err != nil {
		return fmt.Errorf("failed to get copy progress from blob metadata: %w", err)
	}

	if lastCheckpoint > sourceBlobSize {
		// blob is already fully copied
		return nil
	}

	currentOffset := lastCheckpoint
	nextCheckpoint := lastCheckpoint + fastCopy_CheckpointFrequency
	for currentOffset < sourceBlobSize {
		errorsChan := make(chan error, fastCopy_ThreadsPerGroup)
		defer close(errorsChan)

		progressReporter(copyDetailsToOperationProgressUpdate(currentOffset, sourceBlobSize))

		wg := sync.WaitGroup{}
		for threadIndex := int64(0); threadIndex < fastCopy_ThreadsPerGroup; threadIndex++ {
			threadSize := min(fastCopy_PageSize, sourceBlobSize-currentOffset)
			if threadSize <= 0 {
				break
			}

			wg.Add(1)
			go func(ctx context.Context, pageOffset, pageSize int64, wg *sync.WaitGroup) {
				defer wg.Done()

				var err error
				for i := 0; i < fastCopy_CopyAttemptsCountInThread; i++ {
					_, err = dstBlobClient.UploadPagesFromURL(ctx, sourceUrl, pageOffset, pageOffset, pageSize, nil)
					if err == nil {
						break
					}
				}
				if err != nil {
					errorsChan <- err
				}
			}(ctx, currentOffset, threadSize, &wg)

			currentOffset += fastCopy_PageSize
		}

		wg.Wait()

		select {
		case errFromChannel := <-errorsChan:
			return fmt.Errorf("failed to copy file chunk: %w", errFromChannel)
		default:
		}

		if currentOffset > nextCheckpoint {
			c.saveCopyProgressToBlobMetadata(ctx, dstBlobClient, currentOffset)
			nextCheckpoint += fastCopy_CheckpointFrequency
		}

	}

	c.saveCopyProgressToBlobMetadata(ctx, dstBlobClient, fastCopy_CheckpointFullyCopiedValue)

	return nil
}

func (c *AzureClient) CreateStorageAccountIfNotExists(ctx context.Context, storageKey *StorageKey, location string) error {
	operationCtx, cancelFunc := context.WithTimeout(ctx, createStorageAccountTimeout)
	defer cancelFunc()

	exist, err := c.checkResourceExistenceById(operationCtx, storageKey.SubscriptionId, storageKey.StorageResourceId(), apiVersionLatestStable)
	if err != nil {
		return fmt.Errorf("failed to check storage account existence: %w", err)
	} else if exist {
		return nil
	}

	client, err := c.clientBuilder.StorageAccountsClient(storageKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure storage accounts client: %w", err)
	}

	poller, err := client.BeginCreate(
		operationCtx,
		storageKey.ResourceGroup,
		storageKey.StorageAccount,
		armstorage.AccountCreateParameters{
			Kind:     to.Ptr(armstorage.KindStorageV2),
			Location: &location,
			SKU:      &armstorage.SKU{Name: to.Ptr(armstorage.SKUNameStandardLRS)},
			Properties: &armstorage.AccountPropertiesCreateParameters{
				MinimumTLSVersion:    to.Ptr(armstorage.MinimumTLSVersionTLS12),
				AllowSharedKeyAccess: to.Ptr(false),
			},
		},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create storage account: %w", err)
	}

	_, err = poller.PollUntilDone(operationCtx, &runtime.PollUntilDoneOptions{Frequency: createStorageAccountInterval})
	if err != nil {
		return fmt.Errorf("failed to poll storage account creation status: %w", err)
	}

	return nil
}

func (c *AzureClient) CreateStorageAccountContainerIfNotExists(ctx context.Context, containerKey *StorageContainerKey) error {
	exist, err := c.checkResourceExistenceById(ctx, containerKey.SubscriptionId, containerKey.StorageContainerResourceId(), apiVersionLatestStable)
	if err != nil {
		return fmt.Errorf("failed to check storage container existence: %w", err)
	} else if exist {
		return nil
	}

	client, err := c.clientBuilder.StorageContainersClient(containerKey.SubscriptionId)
	if err != nil {
		return fmt.Errorf("failed to initialize azure storage containers client: %w", err)
	}

	_, err = client.Create(
		ctx,
		containerKey.ResourceGroup,
		containerKey.StorageAccount,
		containerKey.Container,
		armstorage.BlobContainer{
			ContainerProperties: &armstorage.ContainerProperties{
				PublicAccess: to.Ptr(armstorage.PublicAccessNone),
			},
		},
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create storage container: %w", err)
	}

	return nil
}

func (c *AzureClient) DeleteBlob(ctx context.Context, blobKey *StorageBlobKey) error {
	client, err := c.clientBuilder.PageBlobClient(blobKey.SubscriptionId, blobKey.BlobUrl())
	if err != nil {
		return fmt.Errorf("failed to initialize page blob client: %w", err)
	}

	_, err = client.GetProperties(ctx, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			// Blob does not exist, nothing to delete
			return nil
		}
		return fmt.Errorf("failed to get blob properties: %w", err)
	}

	_, err = client.Delete(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to delete blob: %w", err)
	}

	return nil
}

func isBlobAlreadyCopying(ctx context.Context, client *pageblob.Client) (bool, error) {
	blobProps, err := client.GetProperties(ctx, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return false, nil
		}

		return false, fmt.Errorf("failed to get blob properties: %w", err)
	}

	if blobProps.CopyStatus == nil {
		return false, nil
	}

	// pending state means that blob is copying at this moment
	// success state means that blob copying is finished but we track it as in-progress state to make sure that we report result properly
	return *blobProps.CopyStatus == blob.CopyStatusTypeSuccess || *blobProps.CopyStatus == blob.CopyStatusTypePending, nil
}

func getSourceVhdBlobSize(ctx context.Context, sourceUrl string) (int64, error) {
	srcBlobClient, err := pageblob.NewClientWithNoCredential(sourceUrl, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to initialize page client for source url: %w", err)
	}

	srcProperties, err := srcBlobClient.GetProperties(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to get blob properties for source url: %w", err)
	}
	if srcProperties.ContentLength == nil {
		return 0, fmt.Errorf("failed to get file size from blob properties for source url: %w", err)
	}

	return *srcProperties.ContentLength, nil
}

func ensureDestinationPageBlobIsCreated(ctx context.Context, client *pageblob.Client, sourceBlobSize int64) error {
	shouldCreateBlob := false
	dstProperties, err := client.GetProperties(ctx, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			// if blob is not found, we should create it
			shouldCreateBlob = true
		} else {
			return fmt.Errorf("failed to get blob properties for destination blob: %w", err)
		}
	} else {
		if dstProperties.ContentLength == nil || *dstProperties.ContentLength != sourceBlobSize {
			// if blob size doesn't equal to expected size, we should create it
			shouldCreateBlob = true
		}
	}

	if shouldCreateBlob {
		_, err = client.Create(ctx, sourceBlobSize, nil)
		if err != nil {
			return fmt.Errorf("failed to create destination blob: %w", err)
		}
	}

	return nil
}

func getCopyProgressFromBlobMetadata(ctx context.Context, client *pageblob.Client) (int64, error) {
	dstProperties, err := client.GetProperties(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to get blob properties for destination blob: %w", err)
	}

	if value, found := dstProperties.Metadata[fastCopy_CheckpointMetadataKey]; found && value != nil && *value != "" {
		parsedValue, err := strconv.ParseInt(*value, 10, 64)
		if err == nil {
			return parsedValue, nil
		}
	}

	return 0, nil
}

func (c *AzureClient) saveCopyProgressToBlobMetadata(ctx context.Context, client *pageblob.Client, copiedBytes int64) {
	metadata := map[string]*string{
		fastCopy_CheckpointMetadataKey: to.Ptr(fmt.Sprint(copiedBytes)),
	}

	if _, err := client.SetMetadata(ctx, metadata, nil); err != nil {
		c.logger.WithError(err).Error("failed to save copy progress to blob metadata")
	}
}
