package azureblob

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	azlog "github.com/Azure/azure-sdk-for-go/sdk/azcore/log"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/github/github-telemetry-go/kvp"
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

// verbatim copy from net/http/transport_default_other.go
func defaultTransportDialContext(dialer *net.Dialer) func(context.Context, string, string) (net.Conn, error) {
	return dialer.DialContext
}

// NewRemoteClient creates a new Azure Blob Storage client using the default Azure SDK authentication mechanism.
func NewRemoteClient(account, container string, logger log.Logger, metrics stats.Client) (*LiveClient, error) {
	idOptions := &azidentity.DefaultAzureCredentialOptions{
		ClientOptions: azcore.ClientOptions{
			// Retry must in total be less than 3 seconds as that
			// is the timeout for the entire transaction
			Retry: policy.RetryOptions{
				MaxRetries: 3,
				TryTimeout: 500 * time.Millisecond,
				RetryDelay: 250 * time.Millisecond,
			},
		},
	}
	credential, err := azidentity.NewDefaultAzureCredential(idOptions)
	if err != nil {
		return nil, err
	}

	serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net/", account)

	httpClient := &http.Client{
		// This is the default http.Transport but with some
		// timeouts shortened
		// https://pkg.go.dev/net/http#RoundTripper
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			DialContext: defaultTransportDialContext(&net.Dialer{
				Timeout:   500 * time.Millisecond,
				KeepAlive: 30 * time.Second,
			}),
			ForceAttemptHTTP2:     true,
			MaxIdleConns:          100,
			TLSHandshakeTimeout:   1 * time.Second,
			ResponseHeaderTimeout: 3 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
	}

	clientOptions := &azblob.ClientOptions{
		ClientOptions: azcore.ClientOptions{
			Transport: httpClient,
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

	azlog.SetListener(AzLogger(logger))
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

func AzLogger(l log.Logger) func(e azlog.Event, s string) {
	return func(e azlog.Event, s string) {
		l.Debug("azlog", kvp.String(string(e), s))
	}
}
