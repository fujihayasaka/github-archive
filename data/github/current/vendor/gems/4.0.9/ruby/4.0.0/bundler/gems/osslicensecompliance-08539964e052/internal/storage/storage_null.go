package storage

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/storage/sequence"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	"gocloud.dev/blob"
)

// NewNullStorage creates a new Storage that uses in-memory blob storage and a SQLite database.
// If you pass an empty string for dbLocation, it will use an in-memory SQLite database.
func NewNullStorage(dbLocation string, logger log.Logger) (*Storage, error) {
	return NewNullStorageWithBuckets(dbLocation, NewNullBucket(), NewNullBucket(), NewNullBucket(), logger)
}

// NewNullStorageWithBuckets creates a new storage with a SQLite database
// and the provided in-memory blob storage buckets.
func NewNullStorageWithBuckets(dbLocation string, repositoryBucket, organizationBucket, enterpriseBucket *NullBucket, logger log.Logger) (*Storage, error) {
	if dbLocation == "" {
		dbLocation = ":memory:"
	}
	db, err := sqlite.New(dbLocation)
	if err != nil {
		return nil, fmt.Errorf("failed to create sqlite database: %w", err)
	}

	storage, err := NewStorage(db, repositoryBucket, organizationBucket, enterpriseBucket, sequence.NewNullGenerator(), stats.NullStatter, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create null storage: %w", err)
	}

	return storage, nil
}

// NullBucket is an in-memory implementation of a blob storage bucket for testing.
// It stores data in memory and is concurrency-safe
type NullBucket struct {
	mu       sync.RWMutex
	data     map[string][]byte
	metadata map[string]time.Time // tracks last modified times
	active   bool
}

var _ BucketReadWriter = &NullBucket{}

// NewNullBucket creates a new NullBucket instance.
func NewNullBucket() *NullBucket {
	return &NullBucket{
		data:     make(map[string][]byte),
		metadata: make(map[string]time.Time),
		active:   true,
	}
}

// WriteAll writes data to the in-memory bucket.
func (n *NullBucket) WriteAll(ctx context.Context, key string, p []byte, opts *blob.WriterOptions) error {
	if !n.active {
		return errors.New("bucket is closed")
	}
	n.mu.Lock()
	defer n.mu.Unlock()

	// Make a copy of the data to avoid issues with the caller modifying the slice
	data := make([]byte, len(p))
	copy(data, p)
	n.data[key] = data
	n.metadata[key] = time.Now()

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

// ReadAllWithMetadata reads data from the in-memory bucket along with its Last-Modified timestamp.
// Returns Azure SDK azcore.ResponseError if the key doesn't exist.
func (n *NullBucket) ReadAllWithMetadata(ctx context.Context, key string) ([]byte, *time.Time, error) {
	if !n.active {
		return nil, nil, errors.New("bucket is closed")
	}
	n.mu.RLock()
	defer n.mu.RUnlock()

	data, ok := n.data[key]
	if !ok {
		return nil, nil, &azcore.ResponseError{
			ErrorCode: string(bloberror.BlobNotFound),
		}
	}

	// Return a copy to avoid the caller modifying our internal data
	result := make([]byte, len(data))
	copy(result, data)

	// Get timestamp
	timestamp := n.metadata[key]
	return result, &timestamp, nil
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

// As is part of the gocloud.dev/blob.Bucket interface.
func (n *NullBucket) As(i any) bool {
	return false
}

// GetLastModified returns the last modified timestamp for a key.
// Returns nil if the key doesn't exist.
func (n *NullBucket) GetLastModified(ctx context.Context, key string) (*time.Time, error) {
	n.mu.RLock()
	defer n.mu.RUnlock()

	if _, exists := n.data[key]; !exists {
		return nil, nil
	}

	t := n.metadata[key]
	return &t, nil
}
