package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	entsql "entgo.io/ent/dialect/sql"
	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/azuresubscription"
	"github.com/github/hosted-compute-ims/gen/ent/imagedefinition"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store/mysql"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (is *ImagesStore) GetAzureSubscriptionById(ctx context.Context, id uint64) (*models.AzureSubscription, error) {
	res, err := is.readEntClient.AzureSubscription.Get(ctx, id)

	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get azure subscription %w", err)
	}

	return AzureSubscriptionFromEnt(res), nil
}

// nolint:gocognit
func (is *ImagesStore) AssignAzureSubscriptionToImageDefinition(ctx context.Context, imageDefinitionId uint64, maxImageDefinitionsPerSubscription int, maxSubscriptionsToQueryInDb int) (uint64, error) {
	image, err := is.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		return 0, err
	}

	// Optimistically retrieve a limited set of subscriptions with availability
	availableSubIds, err := is.getAvailableSubscriptions(ctx, string(image.ImageType), maxImageDefinitionsPerSubscription, maxSubscriptionsToQueryInDb)
	if err != nil {
		return 0, err
	}

	tx, err := is.writeEntClient.Tx(ctx)
	if err != nil {
		return 0, err
	}

	defer func() {
		if p := recover(); p != nil {
			rollbackErr := tx.Rollback()
			if rollbackErr != nil {
				is.logger.WithError(rollbackErr).Error("failed to rollback transaction")
			}

			panic(p)
		}
	}()

	// Within a Tx, retrieve each subscription in turn
	// Validate suitability
	// Attempt to assign the image definition to it
	// On failure try the next subscription
	for _, id := range availableSubIds {
		subscription, err := tx.AzureSubscription.Query().
			Where(
				azuresubscription.IDEQ(uint64(id)),
				azuresubscription.ImageCountLT(maxImageDefinitionsPerSubscription),
			).
			ForUpdate(
				entsql.WithLockAction(entsql.NoWait),
			).Only(ctx)
		if err != nil {
			switch {
			case ent.IsNotFound(err):
				is.logger.WithError(err).Info("subscription is no longer available, trying next subscription...")
				continue
			case mysql.IsLockNoWaitErr(err):
				is.logger.WithError(err).Info("failed to query subscription, trying next subscription...")
				continue
			default:
				is.logger.WithError(err).Info("unexpected error occurred, trying next subscription...")
				continue
			}
		}

		// Attempt to increment the image count for the subscription
		_, err = tx.AzureSubscription.
			UpdateOne(subscription).
			AddImageCount(1).
			Save(ctx)
		if err != nil {
			// Release the previously acquired `FOR UPDATE` lock on the subscription
			if err := tx.Rollback(); err != nil {
				is.logger.WithError(err).Error("failed to rollback transaction")
				return 0, err
			}

			if mysql.IsLockNoWaitErr(err) {
				is.logger.WithError(err).Info("subscription is locked, trying next subscription...")
				continue
			}

			is.logger.WithError(err).Error("failed to increment image count for subscription, trying next subscription...")

			continue
		}

		// Attempt to assign the subscription to the image definition
		updatedCount, err := tx.ImageDefinition.Update().
			Where(
				imagedefinition.IDEQ(imageDefinitionId),
				imagedefinition.AzureSubscriptionIDIsNil(),
			).
			SetAzureSubscriptionID(subscription.ID).
			Save(ctx)
		if err != nil {
			// Release the previously acquired `FOR UPDATE` lock on the subscription
			if err := tx.Rollback(); err != nil {
				is.logger.WithError(err).Error("failed to rollback transaction")
				return 0, err
			}

			is.logger.WithError(err).Error("failed to assign subscription to image definition, trying next subscription...")

			continue
		}

		// If the image definition was not updated, it may have been assigned to another subscription as our WHERE condition would have failed
		// Terminate loop immediately
		if updatedCount != 1 {
			if err := tx.Rollback(); err != nil {
				is.logger.WithError(err).Error("failed to rollback transaction")
				return 0, err
			}

			is.logger.WithError(err).Error("failed to assign subscription to image definition, image definition already assigned subscription...")

			return 0, fmt.Errorf("failed to assign subscription to image definition, image definition already assigned subscription %d", *image.AzureSubscriptionId)
		}

		if err := tx.Commit(); err != nil {
			is.logger.WithError(err).Error("failed to commit transaction")
			return 0, err
		}

		return subscription.ID, nil
	}

	// No subscriptions available
	if err := tx.Rollback(); err != nil {
		is.logger.WithError(err).Error("failed to rollback transaction")
		return 0, err
	}

	return 0, errors.New("no subscriptions currently available")
}

func (is *ImagesStore) UnassignAzureSubscriptionFromImageDefinition(ctx context.Context, imageDefinitionId uint64) error {
	tx, err := is.writeEntClient.Tx(ctx)
	if err != nil {
		return err
	}

	defer func() {
		if p := recover(); p != nil {
			rollbackErr := tx.Rollback()
			if rollbackErr != nil {
				is.logger.WithError(rollbackErr).Error("failed to rollback transaction")
			}

			panic(p)
		}
	}()

	image, err := tx.ImageDefinition.Query().
		Where(
			imagedefinition.IDEQ(imageDefinitionId),
			imagedefinition.AzureSubscriptionIDNotNil(),
		).
		Only(ctx)
	if err != nil {
		if err := tx.Rollback(); err != nil {
			is.logger.WithError(err).Error("failed to rollback transaction")
			return err
		}

		is.logger.WithError(err).Error("failed to unassign azure subscription from image definition may already be unassigned")

		return errors.New("failed to unassign azure subscription from image definition, may already be unassigned")
	}

	_, err = tx.ImageDefinition.UpdateOne(image).
		ClearAzureSubscriptionID().
		Save(ctx)
	if err != nil {
		if err := tx.Rollback(); err != nil {
			is.logger.WithError(err).Error("failed to rollback transaction")
			return err
		}

		is.logger.WithError(err).Error("failed to unassign azure subscription from image definition")

		return errors.New("failed to unassign azure subscription from image definition")
	}

	updatedCount, err := tx.AzureSubscription.Update().
		Where(azuresubscription.IDEQ(*image.AzureSubscriptionID)).
		AddImageCount(-1).
		Save(ctx)
	if err != nil {
		if err := tx.Rollback(); err != nil {
			is.logger.WithError(err).Error("failed to rollback transaction")
			return err
		}

		is.logger.WithError(err).Error("failed to decrement azure subscription image count")

		return errors.New("failed to decrement azure subscription image count")
	}

	if updatedCount != 1 {
		if err := tx.Rollback(); err != nil {
			is.logger.WithError(err).Error("failed to rollback transaction")
			return err
		}

		is.logger.WithError(err).Error("failed to decrement azure subscription image count, does azure subscription exist?")

		return fmt.Errorf("failed to decrement azure subscription image count for subscription with id %d", *image.AzureSubscriptionID)
	}

	if err := tx.Commit(); err != nil {
		is.logger.WithError(err).Error("failed to commit transaction")
		return err
	}

	return nil
}

func (is *ImagesStore) getAvailableSubscriptions(ctx context.Context, imageType string, maxImageDefinitionsPerSubscription int, maxSubscriptionsToQueryInDb int) ([]uint64, error) {
	availableSubIds, err := is.readEntClient.AzureSubscription.Query().
		Where(
			azuresubscription.ImageTypeIn(azuresubscription.ImageType(imageType), azuresubscription.ImageTypeMixed),
			azuresubscription.ImageCountLT(maxImageDefinitionsPerSubscription),
			azuresubscription.SubscriptionIDNEQ(utils.SharedDevImagesSubscriptionId), // it is not allowed to assign image definitions to shared dev subscription
		).
		Order(azuresubscription.ByImageCount(entsql.OrderAsc())).
		Limit(maxSubscriptionsToQueryInDb).
		IDs(ctx)

	return availableSubIds, err
}
