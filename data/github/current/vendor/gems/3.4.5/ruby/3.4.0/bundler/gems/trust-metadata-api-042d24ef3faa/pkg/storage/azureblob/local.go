package azureblob

import (
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

const azuriteAccountName = "devstoreaccount1"

func buildLocalBlobURL(account, container, blobName string) string {
	return fmt.Sprintf("http://127.0.0.1:10000/%s/%s/%s", account, container, blobName)
}

// The Azurite emulator uses shared key authorization, so the SAS params are signed with the shared key
func signSASParamsWithSharedKey(sasParams sas.BlobSignatureValues) (sas.QueryParameters, error) {
	cred, err := blob.NewSharedKeyCredential("devstoreaccount1", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==")
	if err != nil {
		return sas.QueryParameters{}, fmt.Errorf("failed to get user delegation credential: %w", err)
	}

	qps, err := sasParams.SignWithSharedKey(cred)
	if err != nil {
		return sas.QueryParameters{}, fmt.Errorf("failed to build signed blob signature with user delegation key: %w", err)
	}

	return qps, err
}

// NewLocalClient creates a new Azure Blob Storage client using Azurite (a local storage instance) and a connection string
func NewLocalClient(container string) (*LiveClient, error) {
	// Create an Azure blob storage client against the emulator using a connection string
	// documented in https://github.com/Azure/Azurite?tab=readme-ov-file#connection-strings
	conn := "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"
	azClient, err := azblob.NewClientFromConnectionString(conn, nil)
	if err != nil {
		return nil, err
	}

	return &LiveClient{
		account:      azuriteAccountName,
		azClient:     azClient,
		buildBlobURL: buildLocalBlobURL,
		container:    container,
		observability: observabilityConfig{
			logger:  log.NewNullLogger(),
			metrics: stats.NullStatter,
		},
		protocol:      sas.ProtocolHTTPSandHTTP,
		signSASParams: signSASParamsWithSharedKey,
		uploadOpts: azblob.UploadBufferOptions{
			HTTPHeaders: &blob.HTTPHeaders{
				BlobContentType: &snappyUploadContentType,
			},
		},
		uploadLimit: uploadLimitInBytes,
	}, nil
}
