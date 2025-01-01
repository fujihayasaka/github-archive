package launchblob

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/github/go-blob"
	"github.com/github/go-blob/azure"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
)

type BlobConfig struct {
	// Azure SPN Configuration
	AzureSPNClientSecret string `config:",env=AZURE_SPN_CLIENT_SECRET"`
	AzureSPNTenantID     string `config:",env=AZURE_SPN_TENANT_ID"`
	AzureSPNClientID     string `config:",env=AZURE_SPN_CLIENT_ID"`

	// Azure Blob Storage Account Configuration
	AzureStorageAccountCount  int    `config:"3,env=AZURE_BLOB_STORAGE_ACCOUNT_COUNT"`
	AzureStorageAccountPrefix string `config:",env=AZURE_STORAGE_ACCOUNT_PREFIX"`
	AzureStorageContainerName string `config:"payloads,env=AZURE_STORAGE_CONTAINER_NAME"`

	// Development Azurite Blob Config
	AzuriteBlobHost   string `config:",env=AZURITE_BLOB_HOST"`
	AzuriteAccountKey string `config:",env=AZURITE_ACCOUNT_KEY"`
}

func (c *BlobConfig) AzureStorageAccountIDs() []int {
	if launchconfig.IsDevelopment() {
		// in development, we only have one account and it's 1-indexed
		return []int{1}
	}

	accountIDs := make([]int, 0, c.AzureStorageAccountCount)
	for i := 0; i < c.AzureStorageAccountCount; i++ {
		accountIDs = append(accountIDs, i)
	}

	return accountIDs
}

func NewClient(cfg BlobConfig, logger logger.Logger, stats statter.Statter, client *http.Client) (blob.Client, error) {
	accounts := make([]string, 0)
	for i := 0; i < cfg.AzureStorageAccountCount; i++ {
		accounts = append(accounts, fmt.Sprintf("%s%d", cfg.AzureStorageAccountPrefix, i))
	}

	if launchconfig.IsDevelopment() {
		return azure.NewClient(
			accounts,
			azure.WithAccountKeyAuth(cfg.AzuriteAccountKey),
			azure.WithBaseURLFormat(strings.TrimRight(cfg.AzuriteBlobHost, "/")+"/%s"),
			azure.WithLogger(logger.ToOtelLogger()),
			azure.WithHTTPClient(client),
		)
	}

	bc, err := azure.NewClient(
		accounts,
		azure.WithSPNAuth(
			cfg.AzureSPNTenantID,
			cfg.AzureSPNClientID,
			cfg.AzureSPNClientSecret,
		),
		azure.WithLogger(logger.ToOtelLogger()),
		azure.WithStats(stats.Client()),
		azure.WithHTTPClient(client),
	)

	if err != nil {
		return nil, errors.Wrap(err, "creating azure blob client")
	}

	return bc, nil
}
