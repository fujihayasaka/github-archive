// Package storage provides database layer
package storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/go-stats"
	gocloud_blob "gocloud.dev/blob"
)

// ErrNotFound is returned when storage does not contain requested item
var ErrNotFound = errors.New("not found")

// NewStorage creates a new storage instance with the given sql DB
func NewStorage(db *sql.DB, repoBucket, orgBucket, entBucket BucketReadWriter, metrics stats.Client) (*Storage, error) {
	return &Storage{
		db:               db,
		repoBucket:       repoBucket,
		orgBucket:        orgBucket,
		enterpriseBucket: entBucket,
		metrics:          metrics,
	}, nil
}

// BucketReadWriter defines the interface for reading and writing to blob storage buckets.
type BucketReadWriter interface {
	WriteAll(ctx context.Context, key string, p []byte, opts *gocloud_blob.WriterOptions) error
	ReadAll(ctx context.Context, key string) ([]byte, error)
	Delete(ctx context.Context, key string) (err error)
	Close() error
}

// Storage represents the storage SubSystem
type Storage struct {
	db               *sql.DB
	repoBucket       BucketReadWriter
	orgBucket        BucketReadWriter
	enterpriseBucket BucketReadWriter
	metrics          stats.Client
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

// writeAllWithMetrics wraps bucket WriteAll operations with metrics tracking
func (s *Storage) writeAllWithMetrics(ctx context.Context, bucket BucketReadWriter, method, key string, data []byte, opts *gocloud_blob.WriterOptions) error {
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
