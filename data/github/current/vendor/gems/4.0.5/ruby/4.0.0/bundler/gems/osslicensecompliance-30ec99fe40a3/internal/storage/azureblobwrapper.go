package storage

import (
	"context"
	"io"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	"gocloud.dev/blob"
)

// AzureBlobWrapper wraps a gocloud blob.Bucket and adds Azure-specific functionality
// such as retrieving blob metadata (Last-Modified timestamps).
type AzureBlobWrapper struct {
	bucket *blob.Bucket
}

// NewAzureBlobWrapper creates a new wrapper around a gocloud blob.Bucket.
func NewAzureBlobWrapper(bucket *blob.Bucket) *AzureBlobWrapper {
	return &AzureBlobWrapper{bucket: bucket}
}

// WriteAll writes data to a blob.
func (w *AzureBlobWrapper) WriteAll(ctx context.Context, key string, p []byte, opts *blob.WriterOptions) error {
	return w.bucket.WriteAll(ctx, key, p, opts)
}

// ReadAll reads all data from a blob.
func (w *AzureBlobWrapper) ReadAll(ctx context.Context, key string) ([]byte, error) {
	return w.bucket.ReadAll(ctx, key)
}

// ReadAllWithMetadata reads all data from a blob and returns it along with the Last-Modified timestamp
// from the response headers. This is more efficient and safer than making separate ReadAll and GetLastModified calls
// because it gets both atomically in a single operation.
func (w *AzureBlobWrapper) ReadAllWithMetadata(ctx context.Context, key string) ([]byte, *time.Time, error) {
	var containerClient *container.Client
	if !w.bucket.As(&containerClient) {
		// Fallback: use standard ReadAll without metadata if we can't get Azure container client
		data, err := w.bucket.ReadAll(ctx, key)
		return data, nil, err
	}

	blobClient := containerClient.NewBlobClient(key)
	resp, err := blobClient.DownloadStream(ctx, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			return nil, nil, err
		}
		return nil, nil, err
	}

	// Read the body and ensure it's closed
	data, err := io.ReadAll(resp.Body)
	closeErr := resp.Body.Close()
	if err != nil {
		return nil, nil, err
	}
	if closeErr != nil {
		return nil, nil, closeErr
	}

	// Extract Last-Modified from response headers
	return data, resp.LastModified, nil
}

// Delete deletes a blob.
func (w *AzureBlobWrapper) Delete(ctx context.Context, key string) error {
	return w.bucket.Delete(ctx, key)
}

// Close closes the bucket.
func (w *AzureBlobWrapper) Close() error {
	return w.bucket.Close()
}

// As converts the bucket to the specified type.
func (w *AzureBlobWrapper) As(i any) bool {
	return w.bucket.As(i)
}

// GetLastModified retrieves the Last-Modified timestamp for a blob without downloading its contents.
// It uses Azure's GetProperties API which performs a lightweight HEAD request.
// Returns nil if the blob does not exist.
func (w *AzureBlobWrapper) GetLastModified(ctx context.Context, key string) (*time.Time, error) {
	var containerClient *container.Client
	if !w.bucket.As(&containerClient) {
		// Fallback: if we can't get the Azure container client, return nil
		// This shouldn't happen in production but allows graceful degradation
		return nil, nil
	}

	blobClient := containerClient.NewBlobClient(key)
	props, err := blobClient.GetProperties(ctx, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.BlobNotFound) {
			// Blob doesn't exist, return nil timestamp
			return nil, nil
		}
		return nil, err
	}

	return props.LastModified, nil
}
