package sas

import (
	"context"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

const (
	// how many hours into the future should our SAS and user delegation
	// tokens expire. For usage reports, 1 hour should be enough but
	// we will go with 2 hours to be extra safe.
	expiryHours = 2 * time.Hour
)

type AzureSASService struct {
	blobClient        *service.Client
	statter           stats.Client
	storageAccountURL string
}

type SasService interface {
	ReadWriteListSas(container string) (string, error)
}

func New(cfg *config.Config, statter stats.Client, storageAccountURL string) (SasService, error) {
	cred, err := azidentity.NewClientSecretCredential(cfg.KustoSpnTenantId, cfg.KustoSpnClientId, cfg.KustoSpnClientSecret, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error creating client secret credential")
	}

	blobClient, err := service.NewClient(storageAccountURL, cred, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error creating storage client")
	}

	return AzureSASService{
		blobClient:        blobClient,
		statter:           statter,
		storageAccountURL: storageAccountURL,
	}, nil
}

func (s AzureSASService) ReadWriteListSas(container string) (string, error) {
	signatureValues := sas.BlobSignatureValues{
		Protocol:      sas.ProtocolHTTPS,
		StartTime:     time.Now().UTC().Add(-10 * time.Second), // set start time to a few seconds in the past to allow for clock skew
		ExpiryTime:    time.Now().UTC().Add(expiryHours),
		Permissions:   to.Ptr(sas.ContainerPermissions{List: true, Read: true, Write: true}).String(),
		ContainerName: container,
	}

	return s.signSAS(&signatureValues)
}

// signSAS signs the given BlobSignatureValues with a user delegation credential obtained using the identity
// we created the blob client with (this should be from the SPN we created for billing platform).
func (s AzureSASService) signSAS(signatureValues *sas.BlobSignatureValues) (string, error) {
	startTime := time.Now()

	if signatureValues == nil {
		return "", fmt.Errorf("signatureValues must be non-nil")
	}

	keyStart := time.Now().UTC().Add(-10 * time.Second) // set start time to a few seconds in the past to allow for clock skew
	keyExpiry := time.Now().UTC().Add(expiryHours)
	keyInfo := service.KeyInfo{
		Start:  to.Ptr(keyStart.Format(sas.TimeFormat)),
		Expiry: to.Ptr(keyExpiry.Format(sas.TimeFormat)),
	}

	udc, err := s.blobClient.GetUserDelegationCredential(context.Background(), keyInfo, nil)
	if err != nil {
		return "", errors.Wrap(err, "error getting user delegation credential")
	}

	sasQueryParams, err := signatureValues.SignWithUserDelegation(udc)
	if err != nil {
		return "", errors.Wrap(err, "error signing SAS with user delegation")
	}

	// builds URL for the SAS of the form:
	// https://<storageAccount>.blob.core.windows.net/<container>?<sasQueryParams>
	sasURL := fmt.Sprintf("%s/%s?%s", s.storageAccountURL, signatureValues.ContainerName, sasQueryParams.Encode())

	s.statter.Counter("sas.mint.count", nil, 1)
	s.statter.DistributionMs("sas.mint.duration", nil, time.Since(startTime))

	return sasURL, nil
}
