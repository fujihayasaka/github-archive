package azurecommerce

import (
	"context"
	"encoding/json"
	"fmt"

	"strconv"

	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
	"github.com/Azure/azure-sdk-for-go/sdk/keyvault/azsecrets"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azqueue"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/pkg/errors"

	stats "github.com/github/go-stats"
)

type CacheEntry struct {
	value      interface{}
	expiration int64
}

type AzureCommerce struct {
	cache sync.Map
}

const SasTokenCacheKey = "AzureCommerceSasToken"

func NewAzureCommerceClient() *AzureCommerce {
	return &AzureCommerce{}
}

func (ac *AzureCommerce) EmitLineItem(ctx context.Context, statter stats.Client, cfg *config.Config, item *models.Item, azureAccountId string, customerId string, discountQuantity float64) (*models.AzureEmission, error) {
	sasToken, err := ac.GetSasToken(ctx, statter, cfg, false)
	if err != nil {
		return nil, fmt.Errorf("error getting sas token: %w", err)
	}

	usageItem := models.CreateUsageEntity(azureAccountId, item, cfg.AzureCommerceLocation, discountQuantity)

	azureEmissionDetail := &models.AzureEmissionPartitionDetail{
		CustomerId: customerId,
		Sku:        item.GetSku(),
		Year:       int64(item.UsageAt.Year()),
		Month:      int64(item.UsageAt.Month()),
		Day:        int64(item.UsageAt.Day()),
	}
	azureEmission := models.NewAzureEmission(azureEmissionDetail, usageItem, discountQuantity)

	if usageItem.Properties["Quantity"].(float64) == 0 {
		statter.Counter("azure-emission-discount-usage", stats.Tags{"product-sku": item.GetSku()}, int64(1))
		azureEmission.Status = models.AzureEmissionIgnored
		return azureEmission, nil
	}

	// If there is a non zero quantity to emit after discounts are applied we need to verify
	// the azure subscription id is not empty. If it is empty we will not emit the usage and err.
	if azureAccountId == "" {
		azureEmission.Status = models.AzureEmissionFailed
		azureEmission.ErrorMessage = "Azure subscription id is empty"
		return azureEmission, nil
	}

	if err := EmitToPav2Table(ctx, cfg.AzureCommerceTableUri, sasToken, usageItem); err != nil {
		azureEmission.Status = models.AzureEmissionFailed
		azureEmission.ErrorMessage = fmt.Sprintf("Unable to add to table: %s", err.Error())
		return azureEmission, nil
	}

	if err := EmitToPav2Queue(ctx, cfg, sasToken, usageItem); err != nil {
		azureEmission.Status = models.AzureEmissionFailed
		azureEmission.ErrorMessage = fmt.Sprintf("Unable to add to queue: %s", err.Error())
		return azureEmission, nil
	}

	azureEmission.Status = models.AzureEmissionCompleted
	statter.Counter("azure-commerce-emission-completed", stats.Tags{"product-sku": item.GetSku()}, int64(1))

	return azureEmission, nil
}

func (ac *AzureCommerce) GetSasToken(ctx context.Context, statter stats.Client, cfg *config.Config, force bool) (string, error) {
	if !force {
		if cached, ok := ac.cache.Load(SasTokenCacheKey); ok {
			if cached.(CacheEntry).expiration > time.Now().UnixNano() {
				return cached.(CacheEntry).value.(string), nil
			}
		}
	}

	statter.Counter("azure-commerce-sas-token-cache-miss", stats.Tags{"forceCache": strconv.FormatBool(force)}, int64(1))

	cred, err := azidentity.NewClientSecretCredential(cfg.AzureCommerceKeyVaultTenantId, cfg.AzureCommerceSpnClientId, cfg.AzureCommerceSpnClientSecret, nil)
	if err != nil {
		return "", errors.Wrap(err, "error creating credential")
	}

	client, err := azsecrets.NewClient(cfg.AzureCommerceKeyVaultUri, cred, nil)
	if err != nil {
		return "", errors.Wrap(err, "error creating client")
	}

	// An empty string version gets the latest version of the secret.
	version := ""
	resp, err := client.GetSecret(ctx, cfg.AzureCommerceSasTokenSecretName, version, nil)
	if err != nil {
		return "", errors.Wrap(err, "error getting secret")
	}

	// Add 1 day expiration to cached value
	expiration := time.Now().Add(24 * time.Hour).UnixNano()
	value := *resp.Value
	ac.cache.Store(SasTokenCacheKey, CacheEntry{value: value, expiration: expiration})
	return value, nil
}

func EmitToPav2Table(ctx context.Context, azureCommerceTableUri string, sasToken string, usageItem aztables.EDMEntity) error {
	serviceUrl := GetAzureStorageUrl(azureCommerceTableUri, sasToken)
	tableClient, err := NewTablesClient(ctx, serviceUrl)
	if err != nil {
		return errors.Wrap(err, "error getting client")
	}

	marshalled, err := json.Marshal(usageItem)
	if err != nil {
		return errors.Wrap(err, "error marshalling usage")
	}

	_, err = tableClient.AddEntity(ctx, marshalled, nil)
	if err != nil {
		return errors.Wrap(err, "error adding entity")
	}

	return nil
}

func EmitToPav2Queue(ctx context.Context, cfg *config.Config, sasToken string, usageItem aztables.EDMEntity) error {
	serviceUrl := GetAzureStorageUrl(cfg.AzureCommerceQueueUri, sasToken)
	queueClient, err := NewQueueClient(ctx, serviceUrl)
	if err != nil {
		return errors.Wrap(err, "error getting client")
	}

	message, err := models.GenerateAzureQueueMessage(usageItem)
	if err != nil {
		return errors.Wrap(err, "error generating queue message")
	}

	_, err = queueClient.EnqueueMessage(ctx, message, nil)
	if err != nil {
		return errors.Wrap(err, "error adding message to queue")
	}

	return nil
}

func NewTablesClient(ctx context.Context, uri string) (*aztables.Client, error) {
	client, err := aztables.NewClientWithNoCredential(uri, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error creating client")
	}

	return client, nil
}

func NewQueueClient(ctx context.Context, uri string) (*azqueue.QueueClient, error) {
	queueClient, err := azqueue.NewQueueClientWithNoCredential(uri, nil)
	if err != nil {
		return nil, errors.Wrap(err, "error creating client")
	}

	return queueClient, nil
}

func GetAzureStorageUrl(storageUri, sasToken string) string {
	return fmt.Sprintf("%s%s", storageUri, sasToken)
}
