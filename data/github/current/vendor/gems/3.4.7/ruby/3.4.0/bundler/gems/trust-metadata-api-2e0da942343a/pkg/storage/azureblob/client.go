package azureblob

import (
	"bytes"
	"context"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/golang/snappy"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"go.opentelemetry.io/otel/attribute"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/sigstore/sigstore-go/pkg/bundle"
)

var (
	snappyUploadContentType = "application/x-snappy"
	errUploadLimitExceeded  = fmt.Errorf("attestation size exceeds upload limit")
	errInvalidRecord        = fmt.Errorf("invalid record format")
)

const (
	// 1GB upload limit
	uploadLimitInBytes = 1 << 30
	// Placeholder value for the repository ID in blob name for npm package
	// records because npm packages do not have a repository ID
	npmRepoIDPlaceholder         = 0
	metricFailedToDownloadBlob   = "blob_download_fail_count"
	metricFailedToUploadBlob     = "blob_upload_fail_count"
	metricSuccessfulDownloadBlob = "blob_download_success_count"
	metricSuccessfulUploadBlob   = "blob_upload_success_count"
)

type signSASParamsFunc func(sas.BlobSignatureValues) (sas.QueryParameters, error)

type azureClient interface {
	CreateContainer(context.Context, string, *azblob.CreateContainerOptions) (azblob.CreateContainerResponse, error)
	DeleteContainer(context.Context, string, *azblob.DeleteContainerOptions) (azblob.DeleteContainerResponse, error)
	DownloadStream(context.Context, string, string, *azblob.DownloadStreamOptions) (azblob.DownloadStreamResponse, error)
	ServiceClient() *service.Client
	UploadBuffer(context.Context, string, string, []byte, *azblob.UploadBufferOptions) (azblob.UploadBufferResponse, error)
}

type Client interface {
	StoreAttestation(ctx context.Context, r attestation.Record, b *bundle.Bundle) error
	StoreAttestationByName(ctx context.Context, name string, b *bundle.Bundle) error
	DownloadAttestation(ctx context.Context, r attestation.Record) (*protobundle.Bundle, error)
	CreateContainer(ctx context.Context, name string) error
	DeleteContainer(ctx context.Context, name string) error
	GenerateSASUrl(ctx context.Context, r attestation.Record) (string, error)
}

type observabilityConfig struct {
	logger  log.Logger
	metrics stats.Client
}

type LiveClient struct {
	account       string
	azClient      azureClient
	buildBlobURL  func(string, string, string) string
	container     string
	observability observabilityConfig
	protocol      sas.Protocol
	signSASParams signSASParamsFunc
	uploadOpts    azblob.UploadBufferOptions
	uploadLimit   int
}

// UseLocalClient returns true if the provided Azure Blob Storage
// account name matches the harcoded account name for the Azurite container
func UseLocalClient(account string) bool {
	return account == azuriteAccountName
}

func buildBlobName(repoID uint64, createdAt time.Time, recordID uint64) string {
	// set the time zone to UTC before creating a path using the date
	utcCreatedAt := createdAt.UTC()
	formattedCreatedAt := utcCreatedAt.Format("2006/01/02")

	// the .sn postfix indicates the file is compressed with snappy
	blobNameFormat := "%d/%s/%d.json.sn"
	return fmt.Sprintf(blobNameFormat, repoID, formattedCreatedAt, recordID)
}

func BuildBlobNameByDomain(r attestation.Record) (string, error) {
	if r.RepositoryID != nil {
		return buildBlobName(*r.RepositoryID, r.CreatedAt, r.ID), nil
	} else if r.Purl != "" {
		return buildBlobName(npmRepoIDPlaceholder, r.CreatedAt, r.ID), nil
	}
	return "", errInvalidRecord
}

func (c *LiveClient) StoreAttestation(ctx context.Context, r attestation.Record, b *bundle.Bundle) error {
	ctx, span := o11y.NamedSpan(ctx, "Blob_StoreAttestation")
	defer span.End()

	attestationBlobName, err := BuildBlobNameByDomain(r)
	if err != nil {
		return fmt.Errorf("failed to build blob name while storing attestation: %w", err)
	}
	span.SetAttributes(attribute.String("blob_name", attestationBlobName))

	return c.StoreAttestationByName(ctx, attestationBlobName, b)
}

func (c *LiveClient) StoreAttestationByName(ctx context.Context, blobName string, b *bundle.Bundle) error {
	ctx, span := o11y.NamedSpan(ctx, "Blob_StoreAttestationByName")
	defer span.End()

	data, err := b.MarshalJSON()
	if err != nil {
		return &ErrBlobUploadFailed{fmt.Errorf("failed to marshal attestation record: %w", err)}
	}

	if len(data) > c.uploadLimit {
		return errUploadLimitExceeded
	}

	if err = c.uploadBlob(ctx, blobName, data); err != nil {
		return &ErrBlobUploadFailed{fmt.Errorf("failed to store attestation record: %w", err)}
	}

	return nil
}

func (c *LiveClient) uploadBlob(ctx context.Context, blobName string, data []byte) error {
	ctx, span := o11y.NamedSpan(ctx, "Blob_UploadBlob")
	defer span.End()

	var compressed []byte
	compressed = snappy.Encode(compressed, data)

	// create tags for logging
	loggingTags := []kvp.Field{kvp.String("Blob-Name", blobName), kvp.String("Blob-Account", c.account), kvp.String("Blob-Container", c.container)}

	// create a new timer to capture the duration it takes to upload the attestation record to Azure Blob Storage
	metricTimer := stats.NewTimer(c.observability.metrics)

	loggingTags = append(loggingTags, kvp.Int("Blob-Byte-Size", len(compressed)))
	c.observability.logger.Info("Starting blob upload", loggingTags...)
	if _, err := c.azClient.UploadBuffer(ctx, c.container, blobName, compressed, &c.uploadOpts); err != nil {
		if bloberror.HasCode(err, bloberror.ContainerNotFound) {
			return fmt.Errorf("failed to upload blob because container '%s' not found: %w", c.container, err)
		}

		// if blob upload failed, increment the failed upload metric
		// and log the failure
		c.observability.metrics.Counter(metricFailedToUploadBlob, nil, 1)

		blobUploadDuration := metricTimer.Time("blob_upload_duration", nil)
		c.observability.logger.Info(fmt.Sprintf("Blob upload failed in %d ms", blobUploadDuration.Milliseconds()), loggingTags...)
		logContextErr(ctx, c.observability.logger, kvp.String("Blob-Name", blobName))

		return fmt.Errorf("failed to upload blob '%s': %w", blobName, err)
	}

	// if blob upload succeeded, record zero to the failed upload metric
	c.observability.metrics.Counter(metricSuccessfulUploadBlob, nil, 1)

	blobUploadDuration := metricTimer.Time("blob_upload_duration", nil)
	c.observability.logger.Info(fmt.Sprintf("Blob upload completed in %d ms", blobUploadDuration.Milliseconds()), loggingTags...)

	return nil
}

func (c *LiveClient) GenerateSASUrl(ctx context.Context, r attestation.Record) (string, error) {
	_, span := o11y.NamedSpan(ctx, "Blob_GenerateSASUrl")
	defer span.End()

	blobName, err := BuildBlobNameByDomain(r)
	if err != nil {
		return "", fmt.Errorf("failed to build blob name while generating SAS URL: %w", err)
	}

	blobURL := c.buildBlobURL(c.account, c.container, blobName)

	urlParts, err := blob.ParseURL(blobURL)
	if err != nil {
		return "", fmt.Errorf("failed to parse blob URL: %w", err)
	}

	// the SAS token should only allow read access to the blob
	readOnlyBlobPerms := sas.BlobPermissions{
		Read: true,
	}

	// the SAS token should be valid for 1 hour starting 15 minutes ago
	// this is to allow for clock skew between the client and the server
	// as recommended by the Azure documentation
	sasStart := time.Now().UTC().Add(-15 * time.Minute)
	// The SAS URL should be valid for 1 hour
	sasExpiry := sasStart.Add(1 * time.Hour)

	blobSigValues := sas.BlobSignatureValues{
		BlobName:      urlParts.BlobName,
		ContainerName: urlParts.ContainerName,
		ExpiryTime:    sasExpiry,
		Permissions:   readOnlyBlobPerms.String(),
		Protocol:      c.protocol,
		StartTime:     sasStart,
		Version:       sas.Version,
	}

	signedQueryParams, err := c.signSASParams(blobSigValues)
	if err != nil {
		return "", fmt.Errorf("failed to build signed access signature: %w", err)
	}

	endpoint := blobURL + "?" + signedQueryParams.Encode()

	return endpoint, nil
}

func (c *LiveClient) DownloadAttestation(ctx context.Context, r attestation.Record) (*protobundle.Bundle, error) {
	ctx, span := o11y.NamedSpan(ctx, "Blob_DownloadAttestation")
	defer span.End()

	blobName, err := BuildBlobNameByDomain(r)
	if err != nil {
		return nil, fmt.Errorf("failed to build blob name while downloading attestation: %w", err)
	}

	span.SetAttributes(attribute.String("blob_name", blobName))

	return c.DownloadAttestationByName(ctx, blobName)
}

func (c *LiveClient) DownloadAttestationByName(ctx context.Context, blobName string) (*protobundle.Bundle, error) {
	ctx, span := o11y.NamedSpan(ctx, "Blob_DownloadAttestationByName")
	defer span.End()

	raw, err := c.downloadBlob(ctx, blobName)
	if err != nil {
		return nil, &ErrBlobDownloadFailed{err}
	}

	if raw == nil {
		return nil, &ErrBlobDownloadFailed{fmt.Errorf("downloaded blob is nil")}
	}

	var b protobundle.Bundle
	if err = protojson.Unmarshal(raw, &b); err != nil {
		return nil, &ErrBlobDownloadFailed{err}
	}

	return &b, nil
}

func (c *LiveClient) downloadBlob(ctx context.Context, blobName string) ([]byte, error) {
	ctx, span := o11y.NamedSpan(ctx, "Blob_DownloadBlob")
	defer span.End()

	// create tags for logging
	loggingTags := []kvp.Field{kvp.String("Blob-Name", blobName), kvp.String("Blob-Account", c.account), kvp.String("Blob-Container", c.container)}

	// create a new timer to capture the duration it takes to download a bundle blob from Azure Blob Storage
	metricTimer := stats.NewTimer(c.observability.metrics)

	get, err := c.azClient.DownloadStream(ctx, c.container, blobName, nil)
	if err != nil {
		// if blob download failed, increment the failed download metric
		c.observability.metrics.Counter(metricFailedToDownloadBlob, nil, 1)

		blobDownloadDuration := metricTimer.Time("blob_download_duration", nil)
		c.observability.logger.Info(fmt.Sprintf("Blob download failed in %d ms", blobDownloadDuration.Milliseconds()), loggingTags...)
		logContextErr(ctx, c.observability.logger, kvp.String("Blob-Name", blobName))

		return nil, fmt.Errorf("failed to download blob '%s': %w", blobName, err)
	}

	// if blob upload succeeded, record zero to the failed download metric
	c.observability.metrics.Counter(metricFailedToDownloadBlob, nil, 0)

	downloadedData := bytes.Buffer{}
	retryReader := get.NewRetryReader(ctx, &azblob.RetryReaderOptions{})
	if _, err = downloadedData.ReadFrom(retryReader); err != nil {
		return nil, err
	}

	blobDownloadDuration := metricTimer.Time("blob_download_duration", nil)
	loggingTags = append(loggingTags, kvp.Int("Blob-Byte-Size", len(downloadedData.Bytes())))
	c.observability.logger.Info(fmt.Sprintf("Blob download completed in %d ms", blobDownloadDuration.Milliseconds()), loggingTags...)
	c.observability.metrics.Counter(metricSuccessfulDownloadBlob, nil, 1)

	var decompressed []byte
	decompressed, err = snappy.Decode(decompressed, downloadedData.Bytes())
	if err != nil {
		return nil, fmt.Errorf("failed to decompress downloaded data: %w", err)
	}

	return decompressed, nil
}

func (c *LiveClient) CreateContainer(ctx context.Context, name string) error {
	_, err := c.azClient.CreateContainer(ctx, name, nil)
	if err != nil {
		if bloberror.HasCode(err, bloberror.ContainerAlreadyExists) {
			return nil
		}
		return fmt.Errorf("failed to create container %s: %w", name, err)
	}
	return nil
}

func (c *LiveClient) DeleteContainer(ctx context.Context, name string) error {
	_, err := c.azClient.DeleteContainer(ctx, name, nil)
	return err
}

func logContextErr(ctx context.Context, log log.Logger, fields ...kvp.Field) {
	ctxErr := context.Cause(ctx)
	switch ctxErr {
	case nil:
		return
	default:
		log.Info(fmt.Sprintf("context was cancelled because: %s", ctxErr.Error()), fields...)
	}
}
