//nolint:all
package main

// This script generates SAS token for Azure Storage container: "az storage container generate-sas"
// It is intended to be run only in E2E workflow in GitHub Actions CI and only from "script/ci/generate_container_sas_without_azcli"
// Script is written on Golang because GitHub Actions E2E workflow is run on self-hosted runners and self-hosted runners don't have Azure CLI pre-installed
// Generating user-delegated SAS token from Bash is pretty complicated: https://learn.microsoft.com/en-us/rest/api/storageservices/create-user-delegation-sas
// So we use Golang with Azure SDK to simplify implementation. Also, this solution doesn't require any tools pre-installed on self-hosted VM.

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/service"
)

func main() {
	if err := realMain(); err != nil {
		log.Fatal(err)
	}
}

func realMain() error {
	ctx := context.Background()

	tenantId := os.Getenv("AZURE_TENANT_ID")
	clientId := os.Getenv("AZURE_CLIENT_ID")
	idToken := os.Getenv("AZURE_ID_TOKEN")
	storageAccountName := os.Getenv("AZURE_STORAGE_ACCOUNT_NAME")
	storageContainerName := os.Getenv("AZURE_STORAGE_CONTAINER_NAME")
	now := time.Now().UTC().Add(-10 * time.Second)
	expiry := now.Add(2 * time.Hour)

	getAssertion := func(ctx context.Context) (string, error) {
		return idToken, nil
	}

	credentials, err := azidentity.NewClientAssertionCredential(tenantId, clientId, getAssertion, nil)
	if err != nil {
		return fmt.Errorf("failed to initialize credentials: %w", err)
	}

	svcClient, err := service.NewClient(
		fmt.Sprintf("https://%s.blob.core.windows.net", storageAccountName),
		credentials,
		&service.ClientOptions{},
	)
	if err != nil {
		return fmt.Errorf("failed to initialize storage account client: %w", err)
	}

	udc, err := svcClient.GetUserDelegationCredential(ctx, service.KeyInfo{Start: to.Ptr(now.UTC().Format(sas.TimeFormat)), Expiry: to.Ptr(expiry.UTC().Format(sas.TimeFormat))}, nil)
	if err != nil {
		return fmt.Errorf("failed to get user delegation creds: %w", err)
	}

	sasQueryParams, err := sas.BlobSignatureValues{
		Protocol:      sas.ProtocolHTTPS,
		StartTime:     now,
		ExpiryTime:    expiry,
		Permissions:   to.Ptr(sas.ContainerPermissions{Read: true}).String(),
		ContainerName: storageContainerName,
	}.SignWithUserDelegation(udc)
	if err != nil {
		return fmt.Errorf("failed to sign with user delegation creds")
	}

	sasToken := sasQueryParams.Encode()

	fmt.Println(sasToken)

	return nil
}
