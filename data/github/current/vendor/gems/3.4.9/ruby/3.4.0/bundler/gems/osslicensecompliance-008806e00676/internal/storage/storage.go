// Package storage provides database layer
package storage

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	math_rand "math/rand/v2"
	"time"

	"github.com/github/github-telemetry-go/log"
	"google.golang.org/protobuf/proto"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	azblobblob "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blockblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/storage/sequence"
	"gocloud.dev/blob"
)

// ErrNotFound is returned when storage does not contain requested item
var ErrNotFound = errors.New("not found")

// Storage represents the storage SubSystem
type Storage struct {
	db               *sql.DB
	repoBucket       BucketReadWriter
	orgBucket        BucketReadWriter
	enterpriseBucket BucketReadWriter
	sequenceGen      sequence.Generator
	metrics          stats.Client
	logger           log.Logger
}

// NewStorage creates a new storage instance with the given sql DB
func NewStorage(db *sql.DB, repoBucket, orgBucket, entBucket BucketReadWriter, sequenceGen sequence.Generator, metrics stats.Client, logger log.Logger) (*Storage, error) {
	return &Storage{
		db:               db,
		repoBucket:       repoBucket,
		orgBucket:        orgBucket,
		enterpriseBucket: entBucket,
		sequenceGen:      sequenceGen,
		metrics:          metrics,
		logger:           logger,
	}, nil
}

// BucketReadWriter defines the interface for reading and writing to blob storage buckets.
type BucketReadWriter interface {
	WriteAll(ctx context.Context, key string, p []byte, opts *blob.WriterOptions) error
	ReadAll(ctx context.Context, key string) ([]byte, error)
	Delete(ctx context.Context, key string) (err error)
	Close() error
	As(i any) bool
}

const maxSwapRetries = 50

// BlobUpdateFunction is the type of function passed to Swap to compute a new blob value.
type BlobUpdateFunction = func(oldBlob []byte) (newBlob []byte, err error)

// Swap performs an atomic read-modify-write operation on a blob storage object identified by key.
// It is not an error to attempt to swap a non-existent object; in that case, old will be nil.
// The function f is called with the current contents of the object (or nil if it does not exist)
// and returns the new contents to write. If f returns an error, the swap operation is aborted.
// NOTE: The function f may be called multiple times if there are concurrent modifications to the object.
// The implementation will retry up to maxSwapRetries times in the face of concurrent updates.
func Swap(ctx context.Context, bucket BucketReadWriter, key string, f BlobUpdateFunction, opts *blob.WriterOptions) error {
	// If the bucket exposes an Azure container client via As we can perform a
	// server-side conditional update using ETag + If-Match. Check once up
	// front to avoid repeating the As call inside the retry loop.
	var azureContainerClient *container.Client
	conditionalUpdateSupported := bucket.As(&azureContainerClient)
	if !conditionalUpdateSupported {
		// Fallback to unsafeSwap for buckets that do not support conditional updates.
		return unsafeSwap(ctx, bucket, key, f, opts)
	}

	// Attempt up to maxSwapRetries times.
	for i := 0; i < maxSwapRetries; i++ {
		// Let caller compute the new value after we obtain current contents
		// and its ETag from a single provider call.
		bb := azureContainerClient.NewBlockBlobClient(key)

		// Download the blob in a single provider call so we get both the
		// contents and the server ETag atomically (avoids race between a
		// separate ReadAll and GetProperties).
		var old []byte
		var currentETag *azcore.ETag
		dlResp, err := bb.DownloadStream(ctx, nil)
		if err != nil {
			if !bloberror.HasCode(err, bloberror.BlobNotFound) {
				return err
			}
		} else {
			// Read the body into memory.
			// The SDK's Download response exposes a body reader; use io.ReadAll
			// and close the stream when done.
			body := dlResp.Body
			b, rerr := io.ReadAll(body)
			_ = body.Close()
			if rerr != nil {
				return rerr
			}
			old = b
			currentETag = dlResp.ETag
		}

		// Let caller compute the newBlob value.
		newBlob, err := f(old)
		if err != nil {
			return err
		}

		// If the blob did not exist when we read it, attempt to create it only
		// if it still does not exist (If-None-Match="*"). Otherwise, use
		// If-Match with the ETag we just read to ensure we only overwrite when
		// unchanged.
		if old == nil {
			_, err = bb.Upload(ctx, &readSeekCloser{bytes.NewReader(newBlob)}, &blockblob.UploadOptions{
				AccessConditions: &azblob.AccessConditions{
					ModifiedAccessConditions: &azblobblob.ModifiedAccessConditions{
						IfNoneMatch: to.Ptr(azcore.ETagAny),
					},
				},
			})
			if err == nil {
				return nil
			}
			if bloberror.HasCode(err, bloberror.ConditionNotMet) || bloberror.HasCode(err, bloberror.BlobAlreadyExists) {
				// Someone else created it in the meantime; retry after a short jittered backoff.
				jitterySleep()
				continue
			}
			return err
		}

		// Attempt conditional upload using If-Match with the blob's current ETag.
		_, err = bb.Upload(ctx, &readSeekCloser{bytes.NewReader(newBlob)}, &blockblob.UploadOptions{
			AccessConditions: &azblob.AccessConditions{
				ModifiedAccessConditions: &azblobblob.ModifiedAccessConditions{
					IfMatch: currentETag,
				},
			},
		})
		if err == nil {
			return nil
		}
		// If the condition failed, someone else changed the blob in the
		// meantime; retry. Other errors are returned.
		if bloberror.HasCode(err, bloberror.ConditionNotMet) {
			// Someone else changed the blob in the meantime; retry after a short jittered backoff.
			jitterySleep()
			continue
		}
		return err
	}

	return fmt.Errorf("swap failed after %d retries", maxSwapRetries)
}

// unsafeSwap performs a read-modify-write operation without any concurrency control.
// It's not used in production! It's only here so that the in-memory NullBucket can
// implement the Swap function for testing purposes.
func unsafeSwap(ctx context.Context, bucket BucketReadWriter, key string, f BlobUpdateFunction, opts *blob.WriterOptions) error {
	old, err := bucket.ReadAll(ctx, key)
	if err != nil {
		if !bloberror.HasCode(err, bloberror.BlobNotFound) && !errors.Is(err, ErrNotFound) {
			return err
		}
		old = nil
	}

	newBlob, err := f(old)
	if err != nil {
		return err
	}

	return bucket.WriteAll(ctx, key, newBlob, opts)
}

// readSeekCloser adapts a bytes.Reader to the io.ReadSeekCloser expected
// by some Azure SDK methods.
type readSeekCloser struct{ *bytes.Reader }

func (r *readSeekCloser) Close() error { return nil }

func (r *readSeekCloser) Seek(offset int64, whence int) (int64, error) {
	return r.Reader.Seek(offset, whence)
}

// Close closes the storage connections
func (s *Storage) Close() error {
	errs := make([]error, 0)
	if s.db != nil {
		if err := s.db.Close(); err != nil {
			errs = append(errs, err)
		}
	}

	if s.repoBucket != nil {
		if err := s.repoBucket.Close(); err != nil {
			errs = append(errs, err)
		}
	}

	if s.orgBucket != nil {
		if err := s.orgBucket.Close(); err != nil {
			errs = append(errs, err)
		}
	}

	if s.enterpriseBucket != nil {
		if err := s.enterpriseBucket.Close(); err != nil {
			errs = append(errs, err)
		}
	}

	if len(errs) > 0 {
		return errors.Join(errs...)
	}
	return nil
}

// HealthCheck performs a basic connectivity check for all storage components
func (s *Storage) HealthCheck(ctx context.Context) error {
	// Check database connection
	if s.db != nil {
		if err := s.db.PingContext(ctx); err != nil {
			return fmt.Errorf("database ping failed: %w", err)
		}
	}

	// Check blob storage buckets by attempting to list a non-existent key
	// This is a lightweight operation that verifies connectivity without side effects
	buckets := map[string]BucketReadWriter{
		"repository":   s.repoBucket,
		"organization": s.orgBucket,
		"enterprise":   s.enterpriseBucket,
	}

	for name, bucket := range buckets {
		if bucket != nil {
			// Try to read a health check key - this will fail with "not found" if the bucket is working
			// or with a connection error if there's a connectivity issue
			_, err := bucket.ReadAll(ctx, "__health_check__")
			if err != nil {
				if !bloberror.HasCode(err, bloberror.BlobNotFound) && !errors.Is(err, ErrNotFound) {
					return fmt.Errorf("%s bucket health check failed: %w", name, err)
				}
			}
		}
	}

	return nil
}

// writeAllWithMetrics wraps bucket WriteAll operations with metrics tracking
func (s *Storage) writeAllWithMetrics(ctx context.Context, bucket BucketReadWriter, method, key string, data []byte, opts *blob.WriterOptions) error {
	tags := stats.Tags{"method": method}

	start := time.Now()
	err := bucket.WriteAll(ctx, key, data, opts)
	s.metrics.DistributionMs("blob_storage.write.duration", tags, time.Since(start))

	if err != nil {
		s.metrics.Counter("blob_storage.write.error", tags, 1)
		return err
	}

	s.metrics.Counter("blob_storage.write.success", tags, 1)
	return nil
}

// readAllWithMetrics wraps bucket ReadAll operations with metrics tracking
func (s *Storage) readAllWithMetrics(ctx context.Context, bucket BucketReadWriter, method, key string) ([]byte, error) {
	tags := stats.Tags{"method": method}

	start := time.Now()
	data, err := bucket.ReadAll(ctx, key)
	s.metrics.DistributionMs("blob_storage.read.duration", tags, time.Since(start))

	if err != nil {
		s.metrics.Counter("blob_storage.read.error", tags, 1)
		return nil, err
	}

	s.metrics.Counter("blob_storage.read.success", tags, 1)
	return data, nil
}

// swapWithMetrics wraps bucket Swap operations with metrics tracking
// it also wraps the caller's swap function to track its duration and success/failure
func (s *Storage) swapWithMetrics(ctx context.Context, bucket BucketReadWriter, method, key string, f BlobUpdateFunction, opts *blob.WriterOptions) error {
	tags := stats.Tags{"method": method}
	start := time.Now()

	wrappedF := func(oldBlob []byte) (newBlob []byte, err error) {
		fTags := stats.Tags{"method": method}
		fStart := time.Now()
		newBlob, err = f(oldBlob)
		s.metrics.DistributionMs("blob_storage.swap.func.duration", fTags, time.Since(fStart))
		if err != nil {
			s.metrics.Counter("blob_storage.swap.func.error", fTags, 1)
		} else {
			s.metrics.Counter("blob_storage.swap.func.success", fTags, 1)
		}
		return newBlob, err
	}

	err := Swap(ctx, bucket, key, wrappedF, opts)
	s.metrics.DistributionMs("blob_storage.swap.duration", tags, time.Since(start))

	if err != nil {
		s.metrics.Counter("blob_storage.swap.error", tags, 1)
		return err
	}

	s.metrics.Counter("blob_storage.swap.success", tags, 1)
	return nil
}

// jitterySleep sleeps for a small random duration between 1ms and 10ms.
// It is used to add a tiny, randomized backoff to reduce immediate retry
// collisions under heavy contention.
func jitterySleep() {
	// math_rand.IntN(10) returns [0,9], so +1 makes it [1,10] milliseconds.
	time.Sleep(time.Duration(math_rand.IntN(10)+1) * time.Millisecond) //nolint:gosec // nosec G404 - not used for security purposes
}

// ProtoCopy makes a deep copy of a protobuf message using Marshal/Unmarshal.
// Note that a future version of protobuf has a CloneOf function that is equivalent.
// https://go-review.googlesource.com/c/protobuf/+/653536/4/proto/merge.go
func ProtoCopy[T proto.Message](in T) T {
	return proto.Clone(in).(T) //nolint:revive,forcetypeassert // this is good enough for the actual protobuf package
}
