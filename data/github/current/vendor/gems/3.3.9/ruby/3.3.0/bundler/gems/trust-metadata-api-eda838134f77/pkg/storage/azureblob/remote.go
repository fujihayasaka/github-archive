package azureblob

import (
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

func buildRemoteBlobURL(account, container, blobName string) string {
	return fmt.Sprintf("https://%s.blob.core.windows.net/%s/%s", account, container, blobName)
}

// Since shared key authorization is disabled on the live blob storage instances,
// we use user delegation key to sign the SAS
func buildSignSASParamsFunc(udc *UserDelegationKeyRefresher) signSASParamsFunc {
	return func(sasParams sas.BlobSignatureValues) (sas.QueryParameters, error) {
		udc := udc.GetUserDelegationKey()
		qps, err := sasParams.SignWithUserDelegation(udc)
		if err != nil {
			return sas.QueryParameters{}, fmt.Errorf("failed to build signed blob signature with user delegation key: %w", err)
		}

		return qps, err
	}
}

// NewRemoteClient creates a new Azure Blob Storage client using the default Azure SDK authentication mechanism.
func NewRemoteClient(account, container string, logger log.Logger, metrics stats.Client) (*LiveClient, error) {
	credential, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return nil, err
	}

	serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net/", account)
	clientOptions := &azblob.ClientOptions{
		ClientOptions: azcore.ClientOptions{
			Retry: policy.RetryOptions{
				MaxRetries: 3,
				// the timeout used by Dotcom when making requests
				// to TMA is eight seconds
				TryTimeout: 3 * time.Second,
			},
		},
	}
	azClient, err := azblob.NewClient(serviceURL, credential, clientOptions)
	if err != nil {
		return nil, err
	}

	userDelegationKeyRefresher, err := newUserDelegationKeyRefresher(azClient.ServiceClient())
	if err != nil {
		return nil, fmt.Errorf("user delegation key refresher couldn't be created, err: %w", err)
	}

	return &LiveClient{
		account:      account,
		azClient:     azClient,
		buildBlobURL: buildRemoteBlobURL,
		container:    container,
		observability: observabilityConfig{
			logger:  logger,
			metrics: metrics,
		},
		protocol:      sas.ProtocolHTTPS,
		signSASParams: buildSignSASParamsFunc(userDelegationKeyRefresher),
		uploadOpts: azblob.UploadBufferOptions{
			HTTPHeaders: &blob.HTTPHeaders{
				BlobContentType: &snappyUploadContentType,
			},
		},
		uploadLimit: uploadLimitInBytes,
	}, nil
}
