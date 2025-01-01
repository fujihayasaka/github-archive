package commands

import (
	"context"
	"encoding/json"
	"fmt"

	_ "embed"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

//nolint:gochecknoinits
func init() {
	RegisterCommand(Instance{
		Description: "Update Azure subscription",
		Run:         updateAzureSubscriptions,
	})
}

func updateAzureSubscriptions(ctx context.Context, inputArg string, cmd Instance) error { // Process the configuration as needed
	// Gives us the source of truth for Azure subscription data
	// If you want to add new subs then update ./cmd/transitions/library/azure_subscriptions_data.go
	// then run the transition for the stamp you want to update
	// eg `.transitions run <pull-request-url> <environment> azure_subscription_update.go`
	subData := GetAzureSubscriptionData()

	// For example, you can log the number of regions:
	logger.Info(ctx, "Loaded Azure subscription configuration with stamps", kvp.Int("stamps_count", len(subData)))

	dataForCurrentEnv, exists := subData[cmd.Helpers.Config.Env]

	// Check if the current environment exists in the configuration
	if !exists {
		// For now we don't track `dotcom` envs, this ensures it's a noop for those envs
		logger.Info(ctx, "no configuration found for environment, skipping update")
		return nil
	}

	logger.Info(ctx, "Processing Azure subscription data for environment", kvp.String("environment", cmd.Helpers.Config.Env))

	for _, subscription := range dataForCurrentEnv.Subscriptions {
		logger.Info(ctx, "Processing subscription", kvp.String("subscriptionId", subscription.SubscriptionId))

		// Create or update the subscription in the database with the data from the YAML file
		err := cmd.Helpers.ImageStore.UpsertAzureSubscriptionBySubscriptionId(ctx, &subscription)
		if err != nil {
			return fmt.Errorf("failed to upsert Azure subscription: %w", err)
		}
	}

	logger.Info(ctx, "Successfully updated Azure subscriptions", kvp.Int("subscriptions_count", len(dataForCurrentEnv.Subscriptions)))

	subs, err := cmd.Helpers.ImageStore.ListAzureSubscriptions(ctx)
	if err != nil {
		return fmt.Errorf("failed to list Azure subscriptions: %w", err)
	}

	for _, sub := range subs {
		subJSON, err := json.Marshal(sub)
		if err != nil {
			return fmt.Errorf("failed to marshal Azure subscription %d: %w", sub.Id, err)
		}
		logger.Info(ctx, "Azure subscription", kvp.Uint64("DbId", sub.Id), kvp.String("subscriptionId", sub.SubscriptionId), kvp.String("config", string(subJSON)))
	}

	return nil
}
