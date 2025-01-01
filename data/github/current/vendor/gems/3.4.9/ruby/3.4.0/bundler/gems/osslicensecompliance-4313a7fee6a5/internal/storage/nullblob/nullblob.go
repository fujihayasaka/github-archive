// Package nullblob provides an in-memory implementation of a blob storage bucket
// for testing purposes. Data is stored in memory and the implementation is thread-safe.
package nullblob

import (
	"context"
	"errors"
	"sync"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	gocloud_blob "gocloud.dev/blob"
)

// NullBucket is an in-memory implementation of a blob storage bucket for testing.
// It stores data in memory and is concurrency-safe
type NullBucket struct {
	mu     sync.RWMutex
	data   map[string][]byte
	active bool
}

// NewBucket creates a new NullBucket instance.
func NewBucket() *NullBucket {
	return &NullBucket{
		data:   make(map[string][]byte),
		active: true,
	}
}

// WriteAll writes data to the in-memory bucket.
func (n *NullBucket) WriteAll(ctx context.Context, key string, p []byte, opts *gocloud_blob.WriterOptions) error {
	if !n.active {
		return errors.New("bucket is closed")
	}
	n.mu.Lock()
	defer n.mu.Unlock()

	// Make a copy of the data to avoid issues with the caller modifying the slice
	data := make([]byte, len(p))
	copy(data, p)
	n.data[key] = data

	return nil
}

// ReadAll reads data from the in-memory bucket.
// Returns Azure SDK azcore.ResponseError if the key doesn't exist.
// To simulate the behavior of Azure Blob Storage.
func (n *NullBucket) ReadAll(ctx context.Context, key string) ([]byte, error) {
	if !n.active {
		return nil, errors.New("bucket is closed")
	}
	n.mu.RLock()
	defer n.mu.RUnlock()

	data, ok := n.data[key]
	if !ok {
		return nil, &azcore.ResponseError{
			ErrorCode: string(bloberror.BlobNotFound),
		}
	}

	// Return a copy to avoid the caller modifying our internal data
	result := make([]byte, len(data))
	copy(result, data)
	return result, nil
}

// Delete removes data from the in-memory bucket.
func (n *NullBucket) Delete(ctx context.Context, key string) error {
	n.mu.Lock()
	defer n.mu.Unlock()

	delete(n.data, key)
	return nil
}

// Close closes the bucket and clears all data.
func (n *NullBucket) Close() error {
	n.active = false
	n.mu.Lock()
	defer n.mu.Unlock()

	// Clear all data
	n.data = make(map[string][]byte)
	return nil
}
