// Package store encapsulates access to sarif analysis files that have been uploaded.
package store

import (
	"bytes"
	"compress/gzip"
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"fmt"
	"io"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/o11y"

	"github.com/pkg/errors"
	"gocloud.dev/blob"
	"gocloud.dev/blob/azureblob"
	"gocloud.dev/blob/memblob"
	"gocloud.dev/blob/s3blob"
)

type SarifStore interface {
	Open(ctx context.Context) error
	Check(ctx context.Context) error
	Close(ctx context.Context) error
	Download(ctx context.Context, path string) (*bytes.Buffer, error)
	DownloadToWriter(ctx context.Context, path string, w io.Writer) error
	Archive(ctx context.Context, r io.Reader, path string) (string, error)
	Upload(ctx context.Context, sarif io.Reader, path string) error
	Exists(ctx context.Context, path string) (bool, error)
	Delete(ctx context.Context, path string) error

	MaxSarifSize() int64
}

type sarifStore struct {
	maxSarifSize      int64
	initialBufferSize int64
	bucket            *blob.Bucket
	openFn            openFunc
}

var _ SarifStore = (*sarifStore)(nil) // ensure interface is implemented

type openFunc func(ctx context.Context) (*blob.Bucket, error)

const initialBufferThreshold = 2 * 1024 * 1024 // average sarif size (1mb) * 2

// NewSarifStore returns a new instance of the SARIF storage service.
// The config.StorageEngine argument is used to specify which storage engine to use: s3, azure, memory.
// Depending on the selected engines, we will try to access the configuration information from the
// config.Config object.
func NewSarifStore(engine config.StorageEngine, cfg *config.Config) SarifStore {
	var openFn func(ctx context.Context) (*blob.Bucket, error)

	switch engine {
	case config.STORAGE_AZURE:
		openFn = func(ctx context.Context) (*blob.Bucket, error) {
			return GetAzureBucket(ctx, cfg.AzureAccountName, cfg.AzureAccountKey, cfg.AzureContainer, cfg.AzureEndpoint)
		}
	case config.STORAGE_S3:
		openFn = func(ctx context.Context) (*blob.Bucket, error) {
			return GetS3Bucket(cfg.AWSID, cfg.AWSSecret, cfg.AWSRegion, cfg.S3Bucket, cfg.S3Endpoint)
		}
	case config.STORAGE_MEMORY:
		openFn = func(ctx context.Context) (*blob.Bucket, error) {
			return memblob.OpenBucket(nil), nil
		}
	}

	return NewSarifStoreWithOpenFunc(openFn, int64(cfg.MaxSarifSize))
}

func NewSarifStoreWithOpenFunc(openFn func(ctx context.Context) (*blob.Bucket, error), maxSarifSize int64) *sarifStore {
	ss := &sarifStore{
		maxSarifSize: maxSarifSize,
		openFn:       openFn,
	}

	ss.initialBufferSize = maxSarifSize + bytes.MinRead
	// regress until we have the first buffer size on or below a threshold
	// this means that when the buffer size doubles on reading a large sarif document the final doubling will always
	// be exactly MaxSarifSize + MinRead and the limit reader will stop further allocations
	for ss.initialBufferSize >= initialBufferThreshold {
		ss.initialBufferSize /= 2
	}

	return ss
}

// TestMemoryStore implements a basic SarifStore for testing purposes only.
func TestMemoryStore() SarifStore {
	return NewSarifStore(config.STORAGE_MEMORY, &config.Config{})
}

// Open the connection with the underlying storage engine
func (s *sarifStore) Open(ctx context.Context) error {
	appctx.Logger(ctx).Info("Opening storage engines")

	if s.openFn == nil {
		return errors.New("open methods not defined")
	}
	if s.bucket != nil {
		return errors.New("buckets already initialized")
	}

	bucket, err := s.openFn(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to open storage")
	}
	s.bucket = bucket
	err = s.Check(ctx)
	if err != nil {
		return err
	}

	// Do a simple test-read to ensure our credentials and configuration are actually correct.
	_, err = s.bucket.Exists(ctx, "_")
	if err != nil {
		return errors.Wrap(err, "failed to check if bucket exists")
	}

	return nil
}

func (s *sarifStore) Check(ctx context.Context) error {
	if ok, err := s.bucket.IsAccessible(ctx); !ok {
		if err != nil {
			return errors.Wrap(err, "could not establish connection to the bucket")
		} else {
			return errors.New("bucket was not accessible")
		}
	}
	return nil
}

// Close the connection with the underlying storage engine
func (s *sarifStore) Close(ctx context.Context) error {
	appctx.Logger(ctx).Info("Closing storage engines")

	err := s.bucket.Close()
	if err != nil {
		return err
	}
	s.bucket = nil

	return nil
}

// ErrMaximumSizeExceeded is the error returned by Download when an uncompressed SARIF file exceeds
// the maximum allowed size
var ErrMaximumSizeExceeded = errors.New("maximum SARIF size exceeded")
var ErrEmptyPath = errors.New("path cannot be empty")

// Download retrieves the SARIF file specified by path from the given
// bucket, and writes it into a buffer.  The file extension is used to
// decide whether the file is compressed. If so, the file is
// decompressed prior to writing.
func (s *sarifStore) Download(ctx context.Context, path string) (*bytes.Buffer, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	start := time.Now()
	var err error
	defer func() {
		appctx.Stats(ctx).DistributionMs("sarif.download", stats.Tags{"success": strconv.FormatBool(err == nil)}, time.Since(start))
	}()

	if path == "" {
		return nil, ErrEmptyPath
	}
	// Control the amount of allocated memory by starting with a buffer that will eventually double
	// to the size of our limit reader.
	buf := bytes.NewBuffer(make([]byte, 0, s.initialBufferSize))
	err = s.DownloadToWriter(ctx, path, buf)
	return buf, err
}

// DownloadToWriter retrieves the SARIF file specified by path from the given
// bucket, and writes it to the writer.  The file extension is used to
// decide whether the file is compressed. If so, the file is
// decompressed prior to writing.
func (s *sarifStore) DownloadToWriter(ctx context.Context, path string, w io.Writer) error {
	appctx.Logger(ctx).Info("Downloading SARIF file", kvp.String("gh.turboscan.sarif_path", path))

	timeoutCtx, timeoutCancel := context.WithTimeout(ctx, 5*time.Second)
	defer timeoutCancel()

	if s.bucket == nil {
		return errors.New("bucket not initialized")
	}

	r, err := s.bucket.NewReader(timeoutCtx, path, nil)
	if err != nil {
		return o11y.AnnotateError(errors.Wrapf(err, "failed reading"), kvp.String("gh.turboscan.sarif_path", path))
	}

	// We use the filename to detect the type of file:
	// .sarif.gz <- compressed
	// .sarif <- uncompressed
	if strings.HasSuffix(path, ".gz") {
		erroringReader := &erroringReader{Reader: r}

		if uncompressErr := uncompress(w, erroringReader, s.maxSarifSize); uncompressErr != nil {
			err = NewUncompressError(uncompressErr, path)
		}

		// transport errors may be transient and should be prioritized over gzip errors
		if readErr := erroringReader.Error(); readErr != nil {
			err = readErr
		}
	} else {
		_, err = io.Copy(w, NewErrorLimitReader(r, s.maxSarifSize, ErrMaximumSizeExceeded))
	}

	if err != nil {
		err = o11y.AnnotateError(errors.Wrapf(err, "failed to copy to output from the buffer"), kvp.String("gh.turboscan.sarif_path", path))
	}

	closeErr := r.Close()
	if err == nil {
		err = closeErr
	}

	return err
}

// uncompress extracts a maximumSize number of bytes from r to w
// if maximumSize is zero there is no limit
func uncompress(w io.Writer, r io.Reader, maximumSize int64) error {
	gzipReader, err := gzip.NewReader(r)
	if err != nil {
		return err
	}

	_, err = io.Copy(w, NewErrorLimitReader(gzipReader, maximumSize, ErrMaximumSizeExceeded))

	if closeErr := gzipReader.Close(); closeErr != nil {
		if err == nil {
			err = closeErr
		}
	}

	return err
}

func NewUncompressError(cause error, path string) error {
	err := o11y.AnnotateError(errors.Wrapf(cause, "failed decompressing file"), kvp.String("gh.turboscan.sarif_path", path))
	return &UncompressError{err}
}

type UncompressError struct {
	error
}

func (err *UncompressError) Unwrap() error {
	return err.error
}

func (s *sarifStore) Archive(ctx context.Context, sarif io.Reader, archiveDataUrl string) (string, error) {
	sourceURL, err := url.Parse(archiveDataUrl)
	if err != nil {
		return "", errors.Wrap(err, "could not parse sarif archive data url")
	}
	return sourceURL.Path, s.Upload(ctx, sarif, sourceURL.Path)
}

func (s *sarifStore) Upload(ctx context.Context, sarif io.Reader, path string) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	start := time.Now()
	var err error
	defer func() {
		appctx.Stats(ctx).DistributionMs("sarif.upload", stats.Tags{"success": strconv.FormatBool(err == nil)}, time.Since(start))
	}()

	if path == "" {
		return errors.New("path cannot be empty")
	}

	w, err := s.bucket.NewWriter(ctx, path, nil)
	if err != nil {
		return err
	}

	if _, err := io.Copy(w, sarif); err != nil {
		return stderrors.Join(err, w.Close())
	}

	return w.Close()
}

func (s *sarifStore) Exists(ctx context.Context, path string) (bool, error) {
	if path == "" {
		return false, errors.New("path cannot be empty")
	}

	return s.bucket.Exists(ctx, path)
}

func (s *sarifStore) Delete(ctx context.Context, path string) error {
	if path == "" {
		return errors.New("path cannot be empty")
	}

	return s.bucket.Delete(ctx, path)
}

func CreateS3Bucket(awsID, awsSecret, region, bucketURI, endpoint string) (bool, error) {
	c := aws.NewConfig().
		WithCredentials(credentials.NewStaticCredentials(awsID, awsSecret, "")).
		WithRegion(region)

	if endpoint != "" {
		c = c.WithEndpoint(endpoint).WithS3ForcePathStyle(true)
	}

	sess, err := session.NewSession(c)
	if err != nil {
		return false, errors.Wrap(err, "couldn't create AWS session")
	}

	svc := s3.New(sess)
	input := &s3.CreateBucketInput{
		Bucket: aws.String(bucketURI),
		CreateBucketConfiguration: &s3.CreateBucketConfiguration{
			LocationConstraint: aws.String(region),
		},
	}
	_, err = svc.CreateBucket(input)
	if err != nil {
		var awsErr awserr.Error
		if errors.As(err, &awsErr) {
			switch awsErr.Code() {
			case s3.ErrCodeBucketAlreadyOwnedByYou:
				return false, nil
			default:
				return false, errors.Wrap(err, "couldn't create bucket")
			}
		} else {
			return false, errors.Wrap(err, "couldn't create bucket")
		}
	}

	return true, nil
}

func GetS3Bucket(awsID, awsSecret, region, bucketURI, endpoint string) (*blob.Bucket, error) {
	if awsID == "" {
		return nil, errors.New("configure S3_AWS_KEY_ID env variable")
	}
	if awsSecret == "" {
		return nil, errors.New("configure S3_AWS_SECRET_KEY_ID env variable")
	}

	c := aws.NewConfig().
		WithCredentials(credentials.NewStaticCredentials(awsID, awsSecret, "")).
		WithRegion(region)

	if endpoint != "" {
		c = c.WithEndpoint(endpoint).WithS3ForcePathStyle(true)
	}

	sess, err := session.NewSession(c)
	if err != nil {
		return nil, err
	}

	// Context is not used for the s3 implementation. Make this explicit.
	var ctx context.Context = nil
	bucket, err := s3blob.OpenBucket(ctx, sess, bucketURI, nil)
	if err != nil {
		return nil, err
	}

	return bucket, nil
}

func GetAzureBucket(ctx context.Context, accountName, accountKey, containerName, endpoint string) (*blob.Bucket, error) {
	if accountKey != "" {
		opts := azureblob.NewDefaultServiceURLOptions()
		opts.AccountName = accountName

		if endpoint != "" {
			endpointURL, err := url.Parse(endpoint)
			if err != nil {
				return nil, errors.Wrap(err, "failed to parse endpoint")
			}

			opts.IsLocalEmulator = true
			opts.Protocol = endpointURL.Scheme
			opts.StorageDomain = endpointURL.Host
		}

		serviceURL, err := azureblob.NewServiceURL(opts)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create service url")
		}

		credential, err := azblob.NewSharedKeyCredential(accountName, accountKey)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create credential")
		}

		client, err := container.NewClientWithSharedKeyCredential(fmt.Sprintf("%s/%s", serviceURL, containerName), credential, nil)
		if err != nil {
			return nil, errors.Wrap(err, "failed to create service client")
		}

		// Create a *blob.Bucket.
		bucket, err := azureblob.OpenBucket(ctx, client, nil)
		if err != nil {
			return nil, errors.Wrap(err, "failed to open bucket")
		}

		return bucket, nil
	} else {
		// If we don't have an account key, use a managed service identity. This can currently only be done by opening the bucket with a URI.
		bucket, err := blob.OpenBucket(ctx, fmt.Sprintf("azblob://%s", containerName))
		if err != nil {
			return nil, errors.Wrap(err, "failed to open bucket")
		}
		return bucket, nil
	}
}

func (s *sarifStore) MaxSarifSize() int64 {
	return s.maxSarifSize
}
