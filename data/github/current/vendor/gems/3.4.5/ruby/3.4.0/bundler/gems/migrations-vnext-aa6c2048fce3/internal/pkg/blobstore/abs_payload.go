// Package blobstore contains the implementation to store and retrieve payloads from the Azure Blob Store.
package blobstore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/Azure/azure-storage-blob-go/azblob"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// Store is the struct to storing and retrieving payloads from the Azure Blob Store
type Store struct {
	containerURL  *azblob.ContainerURL
	credential    *azblob.SharedKeyCredential
	containerName string
	logger        log.Logger
}

// SASGenerator defines the behavior required to handle signed URLs.
type SASGenerator interface {
	BlobPath(kind v1.AssetKind, blobName string) string
	GenerateSignedURL(kind v1.AssetKind, blobName, contentType string, fileSizeBytes int64) (url.URL, error)
}

// NewStore creates a new Store
func NewStore(ctx context.Context, azureURL, accountName, accountKey, container string, logger log.Logger) (*Store, error) {
	creds, err := azblob.NewSharedKeyCredential(accountName, accountKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create shared key credential: %w", err)
	}
	cURL, err := url.Parse(fmt.Sprintf("%s/%s/%s", azureURL, accountName, container))
	if err != nil {
		return nil, fmt.Errorf("failed to parse container url: %w", err)
	}
	pipe := azblob.NewPipeline(creds, azblob.PipelineOptions{})
	containerURL := azblob.NewContainerURL(*cURL, pipe)

	// TODO: remove this at some point: to ease manual testing, we create the container here for now.
	_, _ = containerURL.Create(ctx, azblob.Metadata{}, azblob.PublicAccessNone) //nolint:errcheck // we don't care if it fails
	logger = logger.WithFields(kvp.String("component", "abs-payloads"))

	return &Store{
		containerURL:  &containerURL,
		credential:    creds,
		containerName: container,
		logger:        logger,
	}, nil
}

// WritePayload writes the payload for the given key
func (a *Store) WritePayload(ctx context.Context, namespace, key string, payload []byte) error {
	if namespace == "" {
		return errors.New("namespace cannot be empty")
	}
	key = fmt.Sprintf("%s/%s", namespace, key)

	a.logger.Info("storing payload", kvp.String("key", key))

	_, err := a.containerURL.NewBlockBlobURL(key).Upload(
		ctx,
		strings.NewReader(string(payload)),
		azblob.BlobHTTPHeaders{},
		azblob.Metadata{},
		azblob.BlobAccessConditions{},
		azblob.DefaultAccessTier,
		nil,
		azblob.ClientProvidedKeyOptions{},
		azblob.ImmutabilityPolicyOptions{},
	)
	if err != nil {
		return fmt.Errorf("failed to upload payload: %w", err)
	}

	return nil
}

// GetPayload gets the payload for the given key
func (a *Store) GetPayload(ctx context.Context, namespace, key string) ([]byte, error) {
	if namespace == "" {
		return nil, errors.New("namespace cannot be empty")
	}
	key = fmt.Sprintf("%s/%s", namespace, key)

	a.logger.Info("getting payload", kvp.String("key", key))

	get, err := a.containerURL.NewBlockBlobURL(key).Download(
		ctx,
		0,
		0,
		azblob.BlobAccessConditions{},
		false,
		azblob.ClientProvidedKeyOptions{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to download payload: %w", err)
	}

	resp := get.Body(azblob.RetryReaderOptions{MaxRetryRequests: 20})
	defer func() { _ = resp.Close() }()
	payload, err := io.ReadAll(resp)
	if err != nil {
		return nil, fmt.Errorf("failed to read payload: %w", err)
	}

	return payload, nil
}

func assetKindToPrefix(k v1.AssetKind) string {
	switch k {
	case v1.AssetKind_ASSET_KIND_RELEASE_ASSET:
		return "releases"
	case v1.AssetKind_ASSET_KIND_USER_ASSET:
		return "user-asset"
	default:
		return ""
	}
}

// GenerateSignedURL returns a valid URL for a client to use to upload a blob. URLs are constructed with
// the configured container information, prefix, and blobName.
// TODO Blob paths need to be namespaced to migrations, enterprises etc.
func (a *Store) GenerateSignedURL(kind v1.AssetKind, blobName, contentType string, fileSizeBytes int64) (url.URL, error) {
	blobPath := path.Join(assetKindToPrefix(kind), blobName)
	sasQueryParams, err := azblob.BlobSASSignatureValues{
		Protocol:      azblob.SASProtocolHTTPSandHTTP, // HTTP required for Azurite.
		ContainerName: a.containerName,
		BlobName:      blobPath,
		Permissions:   azblob.BlobSASPermissions{Write: true, Create: true}.String(),
		StartTime:     time.Now().UTC(),
		ExpiryTime:    time.Now().UTC().Add(time.Minute * 5),
	}.NewSASQueryParameters(a.credential)
	if err != nil {
		return url.URL{}, fmt.Errorf("failed to create SAS query parameters: %w", err)
	}
	blobURL := a.containerURL.NewBlockBlobURL(blobPath)
	sasURL := blobURL.URL()
	qs := sasQueryParams.Encode()
	sasURL.RawQuery = qs
	return sasURL, nil
}

// BlobPath returns the key of a blob given the blob name and prefix.
// TODO Blob paths need to be namespaced to migrations, enterprises etc.
func (a *Store) BlobPath(kind v1.AssetKind, blobName string) string {
	return path.Join(assetKindToPrefix(kind), blobName)
}

// GetBlobStream returns an open io.ReaderCloser to read blob data from. The caller must close this stream.
func (a *Store) GetBlobStream(ctx context.Context, key string) (io.ReadCloser, error) {
	blobURL := a.containerURL.NewBlockBlobURL(key)
	resp, err := blobURL.Download(
		ctx,
		0,
		azblob.CountToEnd,
		azblob.BlobAccessConditions{},
		false,
		azblob.ClientProvidedKeyOptions{},
	)
	if err != nil {
		return nil, fmt.Errorf("could not initiate download: %w", err)
	}

	stream := resp.Body(azblob.RetryReaderOptions{})
	return stream, nil
}
