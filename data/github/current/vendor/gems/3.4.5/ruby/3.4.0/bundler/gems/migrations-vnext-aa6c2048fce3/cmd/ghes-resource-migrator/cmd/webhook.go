package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	"github.com/github/migrations-vnext/internal/pkg/set"
	ogithub "github.com/google/go-github/v65/github"
)

func createWebhookForRepository(ctx context.Context, idPath string, c *github.Client, owner, repository, webhookURL string, logger log.Logger) error {
	// If the webhook ID file already exists, skip the creation
	if webhookIDExists(idPath) {
		logger.Info("webhook ID file already exists, skipping creation")
		return nil
	}

	// Try to create the webhook
	hook, resp, err := c.Repositories.CreateHook(ctx, owner, repository, &ogithub.Hook{
		Active: pointer.Of(true),
		Config: &ogithub.HookConfig{
			ContentType: pointer.Of("json"),
			InsecureSSL: pointer.Of("1"),
			URL:         pointer.Of(webhookURL),
		},
		Events: []string{"*"},
	})
	if err != nil {
		return fmt.Errorf("error creating webhook: %w", err)
	}
	defer func() {
		if resp != nil {
			_ = resp.Body.Close()
		}
	}()

	if hook == nil {
		return errors.New("webhook creation returned nil")
	}
	// Save the webhook ID to a file for later use
	if err := saveWebhookID(idPath, hook.GetID()); err != nil {
		return fmt.Errorf("error saving webhook ID: %w", err)
	}

	logger.Info("webhook created successfully", kvp.Int64("id", hook.GetID()))
	return nil
}

func redeliverFailedWebhooks(ctx context.Context, idPath string, c *github.Client, owner, repository string, logger log.Logger) error {
	// check if the webhook ID file exists, if not, skip redelivery
	if !webhookIDExists(idPath) {
		logger.Info("webhook ID file does not exist, skipping redelivery")
		return nil
	}

	// read the webhook ID from the file
	webhookID, err := readWebhookID(idPath)
	if err != nil {
		return fmt.Errorf("error reading webhook ID: %w", err)
	}

	// Wait for 2 seconds before redelivering failed webhooks to give the server time to start
	// and process any incoming webhooks. TODO: replace this for a health check to the server.
	select {
	case <-time.NewTimer(2 * time.Second).C:
	case <-ctx.Done():
		return nil
	}

	// iterate over the webhook deliveries
	var opts ogithub.ListCursorOptions
	opts.PerPage = 100
	var checked int64

	// map to keep track of already delivered webhooks
	delivered := set.Set[string]{}

	log.Info("listing webhook deliveries", kvp.Int64("webhook_id", webhookID))
	for {
		deliveries, resp, err := c.Repositories.ListHookDeliveries(ctx, owner, repository, webhookID, &opts)
		if err != nil {
			return fmt.Errorf("error listing webhook deliveries: %w", err)
		}

		checked += int64(len(deliveries))
		// for each delivery, check if the status is not "OK", if so, redeliver
		for _, delivery := range deliveries {
			// skip if the status is "OK", redelivery is not needed
			if delivery.GetStatus() == "OK" {
				delivered.Add(delivery.GetGUID())
				continue
			}
			// skip if the delivery is a redelivery
			if delivery.GetRedelivery() {
				continue
			}
			// skip if the delivery is already delivered
			if delivered.Contains(delivery.GetGUID()) {
				continue
			}
			// redeliver the webhook
			log.Info("redelivering failed webhook", kvp.String("status", delivery.GetStatus()), kvp.Int64("webhook_id", webhookID), kvp.String("guid", delivery.GetGUID()))
			_, _, err := c.Repositories.RedeliverHookDelivery(ctx, owner, repository, webhookID, delivery.GetID())
			if err != nil && !isAcceptedError(err) {
				return fmt.Errorf("error redelivering webhook: %w", err)
			}
		}

		// check if there are more deliveries to process, otherwise we are done
		if len(deliveries) < opts.PerPage {
			logger.Info("no more deliveries to process", kvp.Int64("checked", checked))
			break
		}
		opts.Cursor = resp.Cursor
	}

	return nil
}

// readWebhookID reads the webhook ID from the specified file.
func readWebhookID(filePath string) (int64, error) { //nolint:unused // will be used in the next PR
	data, err := os.ReadFile(filePath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return 0, fmt.Errorf("error reading webhook ID file: %w", err)
	}
	if len(data) == 0 {
		return 0, errors.New("webhook ID file is empty")
	}
	var webhookID int64
	if _, err := fmt.Sscanf(string(data), "%d", &webhookID); err != nil {
		return 0, fmt.Errorf("error parsing webhook ID: %w", err)
	}
	return webhookID, nil
}

// webhookIDExists checks if the webhook ID file exists.
func webhookIDExists(filePath string) bool {
	_, err := os.Stat(filePath)
	return !errors.Is(err, os.ErrNotExist)
}

// saveWebhookID saves the webhook ID to the specified file.
func saveWebhookID(filePath string, webhookID int64) error {
	if err := os.WriteFile(filePath, []byte(fmt.Sprintf("%d", webhookID)), 0o600); err != nil {
		return fmt.Errorf("error writing webhook ID file: %w", err)
	}
	return nil
}

// isAcceptedError checks if the error is an AcceptedError.
func isAcceptedError(err error) bool {
	var acceptedError *ogithub.AcceptedError
	return errors.As(err, &acceptedError)
}
