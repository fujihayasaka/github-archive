package azureblob

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
	"github.com/github/trust-metadata-api/pkg/attestation"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"google.golang.org/protobuf/encoding/protojson"
)

func NewInMemoryClient() *InMemoryClient {
	return &InMemoryClient{
		blobs: make(map[string][]byte),
	}
}

type InMemoryClient struct {
	blobs map[string][]byte
}

func (c *InMemoryClient) StoreAttestation(ctx context.Context, r attestation.Record, b *bundle.Bundle) error {
	name, err := BuildBlobNameByDomain(r)
	if err != nil {
		return err
	}

	return c.StoreAttestationByName(ctx, name, b)
}

func (c *InMemoryClient) StoreAttestationByName(_ context.Context, blobName string, b *bundle.Bundle) error {
	bytes, err := b.MarshalJSON()
	if err != nil {
		return err
	}
	c.blobs[blobName] = bytes
	return nil
}

func (c *InMemoryClient) DownloadAttestation(_ context.Context, r attestation.Record) (*protobundle.Bundle, error) {
	name, err := BuildBlobNameByDomain(r)
	if err != nil {
		return nil, err
	}

	bytes, found := c.blobs[name]
	if !found {
		respErr := azcore.ResponseError{
			ErrorCode: string(bloberror.BlobNotFound),
		}

		return nil, &respErr
	}

	var b protobundle.Bundle
	if err := protojson.Unmarshal(bytes, &b); err != nil {
		return nil, err
	}

	return &b, nil
}

func (c *InMemoryClient) CreateContainer(context.Context, string) error {
	return nil
}

func (c *InMemoryClient) DeleteContainer(context.Context, string) error {
	return nil
}

func (c *InMemoryClient) GenerateSASUrl(_ context.Context, r attestation.Record) (string, error) {
	name, err := BuildBlobNameByDomain(r)
	if err != nil {
		return "", err
	}

	if _, ok := c.blobs[name]; !ok {
		return "", fmt.Errorf("failed to generate SAS")
	}

	return fmt.Sprintf("some-signed-access-signature-for-%d", r.ID), nil
}

func (c *InMemoryClient) ServiceClient() *service.Client {
	return nil
}
