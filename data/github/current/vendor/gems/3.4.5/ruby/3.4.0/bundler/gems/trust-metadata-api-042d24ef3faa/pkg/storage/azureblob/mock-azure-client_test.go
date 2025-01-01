package azureblob

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
	"github.com/github/trust-metadata-api/pkg/attestation"
)

type MockAzureClient struct{}

func (c *MockAzureClient) UploadBuffer(context.Context, string, string, []byte, *azblob.UploadBufferOptions) (azblob.UploadBufferResponse, error) {
	return azblob.UploadBufferResponse{}, nil
}

func (c *MockAzureClient) DownloadStream(context.Context, string, string, *azblob.DownloadStreamOptions) (azblob.DownloadStreamResponse, error) {
	return azblob.DownloadStreamResponse{}, nil
}

func (c *MockAzureClient) CreateContainer(context.Context, string, *azblob.CreateContainerOptions) (azblob.CreateContainerResponse, error) {
	return azblob.CreateContainerResponse{}, nil
}

func (c *MockAzureClient) DeleteContainer(context.Context, string, *azblob.DeleteContainerOptions) (azblob.DeleteContainerResponse, error) {
	return azblob.DeleteContainerResponse{}, nil
}

func (c *MockAzureClient) GenerateSAS(context.Context, attestation.Record) (string, error) {
	return "", nil
}

func (c *MockAzureClient) ServiceClient() *service.Client {
	return nil
}

type UploadFailureClient struct {
	MockAzureClient
}

func (c *UploadFailureClient) UploadBuffer(context.Context, string, string, []byte, *azblob.UploadBufferOptions) (azblob.UploadBufferResponse, error) {
	return azblob.UploadBufferResponse{}, fmt.Errorf("upload failed")
}

type GenerateSASFailureClient struct {
	MockAzureClient
}

func (c *GenerateSASFailureClient) GenerateSAS(context.Context, attestation.Record) (string, error) {
	return "", fmt.Errorf("failed to generate SAS")
}
