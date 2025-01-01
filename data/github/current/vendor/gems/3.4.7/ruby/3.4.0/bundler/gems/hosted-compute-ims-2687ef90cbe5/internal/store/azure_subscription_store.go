package store

import (
	"cmp"
	"context"
	"database/sql"
	"fmt"
	"math/rand/v2"
	"slices"

	entsql "entgo.io/ent/dialect/sql"
	"github.com/github/hosted-compute-ims/gen/ent"
	"github.com/github/hosted-compute-ims/gen/ent/azuresubscription"
	"github.com/github/hosted-compute-ims/gen/ent/imageversion"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (is *ImagesStore) ListAzureSubscriptions(ctx context.Context) ([]*models.AzureSubscription, error) {
	entSubscriptions, err := is.readEntClient.AzureSubscription.Query().All(ctx)
	if err != nil {
		return nil, err
	}

	var modelsSubscriptions []*models.AzureSubscription
	for _, entSubscription := range entSubscriptions {
		modelsSubscriptions = append(modelsSubscriptions, AzureSubscriptionFromEnt(entSubscription))
	}

	return modelsSubscriptions, nil
}

func (is *ImagesStore) GetAzureSubscriptionById(ctx context.Context, id uint64) (*models.AzureSubscription, error) {
	res, err := is.readEntClient.AzureSubscription.Get(ctx, id)

	if ent.IsNotFound(err) {
		return nil, sql.ErrNoRows
	} else if err != nil {
		return nil, fmt.Errorf("sql: unable to get azure subscription %w", err)
	}

	return AzureSubscriptionFromEnt(res), nil
}

func (is *ImagesStore) UpsertAzureSubscriptionBySubscriptionId(ctx context.Context, sub *models.AzureSubscriptionUpsert) error {
	var err error
	// Check if subscription already exists
	existingSub, err := is.writeEntClient.AzureSubscription.Query().
		Where(azuresubscription.SubscriptionID(sub.SubscriptionId)).
		First(ctx)
	if err != nil && !ent.IsNotFound(err) {
		return fmt.Errorf("failed to check if subscription exists: %w", err)
	}

	if existingSub != nil {
		err = is.writeEntClient.AzureSubscription.UpdateOneID(existingSub.ID).
			SetImageType(azuresubscription.ImageType(sub.ImageType)).
			SetResourcesPrefix(sub.ResourcesPrefix).
			SetImageVersionsLimit(sub.ImageVersionsLimit).
			Exec(ctx)
	} else {
		err = is.writeEntClient.AzureSubscription.Create().
			SetSubscriptionID(sub.SubscriptionId).
			SetImageType(azuresubscription.ImageType(sub.ImageType)).
			SetResourcesPrefix(sub.ResourcesPrefix).
			SetImageVersionsLimit(sub.ImageVersionsLimit).
			Exec(ctx)
	}
	if err != nil {
		return fmt.Errorf("failed to upsert azure subscription: %w", err)
	}
	return nil
}

func (is *ImagesStore) AssignAzureSubscriptionToImageVersion(ctx context.Context, imageVersionId uint64) (*models.ImageVersion, error) {
	imageVersion, err := is.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get image version by id: %w", err)
	}

	if imageVersion.AzureSubscriptionId != nil {
		// azure subscription is already assigned to image version
		return imageVersion, nil
	}

	candidates, err := is.getAzureSubscriptionCandidates(ctx, imageVersion.ImageDefinitionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get azure subscription candidates: %w", err)
	}

	if len(candidates) == 0 {
		return nil, fmt.Errorf("no available azure subscriptions for image version assignment")
	}

	// we need multiple azure subscription candidates to handle race condition cases
	for _, candidate := range candidates {
		successfullyAssigned, err := is.attemptToAssignAzureSubscriptionToImageVersion(ctx, imageVersionId, candidate.ID)
		if err != nil {
			return nil, err
		}

		if successfullyAssigned {
			return is.GetImageVersionById(ctx, imageVersionId)
		}
	}

	return nil, fmt.Errorf("failed to assign azure subscription to image version after checking all candidates")
}

func (is *ImagesStore) UnassignAzureSubscriptionFromImageVersion(ctx context.Context, imageVersionId uint64) error {
	imageVersion, err := is.GetImageVersionById(ctx, imageVersionId)
	if err != nil {
		return fmt.Errorf("failed to get image version by id: %w", err)
	}

	if imageVersion.AzureSubscriptionId == nil {
		return nil
	}

	txErr := withTx(ctx, is.writeEntClient, func(tx *ent.Tx) error {
		client := tx.Client()

		if _, err := client.ImageVersion.UpdateOneID(imageVersionId).
			ClearAzureSubscriptionID().
			Save(ctx); err != nil {
			return fmt.Errorf("failed to clear azure subscription from image version")
		}

		if _, err := client.AzureSubscription.UpdateOneID(*imageVersion.AzureSubscriptionId).
			AddImageVersionsCount(-1).
			Save(ctx); err != nil {
			return fmt.Errorf("failed to decrement image versions count for subscription: %w", err)
		}

		return nil
	})
	if txErr != nil {
		return txErr
	}

	return nil
}

func (is *ImagesStore) getAzureSubscriptionCandidates(ctx context.Context, imageDefinitionId uint64) ([]*ent.AzureSubscription, error) {
	imageDefinition, err := is.readEntClient.ImageDefinition.Get(ctx, imageDefinitionId)
	if err != nil {
		return nil, fmt.Errorf("failed to get image definition by id: %w", err)
	}

	// retrieve all azure subscriptions which are already assigned to other versions of this image definition
	var subscriptionIdsAlreadyAssignedToImageDefinition []uint64
	if err := is.readEntClient.ImageVersion.Query().
		Where(
			imageversion.ImageDefinitionIDEQ(imageDefinitionId),
			imageversion.AzureSubscriptionIDNotNil(),
		).
		GroupBy(imageversion.FieldAzureSubscriptionID).
		Scan(ctx, &subscriptionIdsAlreadyAssignedToImageDefinition); err != nil {
		return nil, fmt.Errorf("failed to retrieve already assigned azure subscriptions for image definition: %w", err)
	}

	allCandidatesSubscriptions, err := is.readEntClient.AzureSubscription.Query().
		Where(
			azuresubscription.ImageTypeIn(azuresubscription.ImageType(imageDefinition.ImageType), azuresubscription.ImageTypeMixed),
			azuresubscription.SubscriptionIDNEQ(utils.SharedDevImagesSubscriptionId), // it is not allowed to assign image definitions to shared dev subscription
			sqlPredicateSubscriptionHasFreeSlots,
		).All(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get available azure subscriptions: %w", err)
	}

	candidatesAlreadyUsed := []*ent.AzureSubscription{}
	candidatesNotUsedYet := []*ent.AzureSubscription{}
	for _, subscription := range allCandidatesSubscriptions {
		if slices.Contains(subscriptionIdsAlreadyAssignedToImageDefinition, subscription.ID) {
			candidatesAlreadyUsed = append(candidatesAlreadyUsed, subscription)
		} else {
			candidatesNotUsedYet = append(candidatesNotUsedYet, subscription)
		}
	}

	// sort already used candidates by ID
	slices.SortFunc(candidatesAlreadyUsed, func(a, b *ent.AzureSubscription) int { return cmp.Compare(a.ID, b.ID) })
	// shuffle not used yet candidates to randomly choose new azure subscription
	rand.Shuffle(len(candidatesNotUsedYet), func(i, j int) {
		candidatesNotUsedYet[i], candidatesNotUsedYet[j] = candidatesNotUsedYet[j], candidatesNotUsedYet[i]
	})

	return append(candidatesAlreadyUsed, candidatesNotUsedYet...), nil
}

func (is *ImagesStore) attemptToAssignAzureSubscriptionToImageVersion(ctx context.Context, imageVersionId uint64, azureSubscriptionId uint64) (bool, error) {
	successfullyAssigned := false

	txErr := withTx(ctx, is.writeEntClient, func(tx *ent.Tx) error {
		client := tx.Client()

		updatedSubsCount, err := client.AzureSubscription.Update().
			Where(
				azuresubscription.IDEQ(azureSubscriptionId),
				sqlPredicateSubscriptionHasFreeSlots,
			).
			AddImageVersionsCount(1).
			Save(ctx)
		if err != nil {
			return fmt.Errorf("failed to increment image versions count for subscription: %w", err)
		}

		if updatedSubsCount < 1 {
			// it might happen because of race condition between finding subscription candidates and subscription assignment
			// subscription can already reach image version limit because of it and "sqlPredicateSubscriptionHasFreeSlots" will prevent using subscription
			return nil
		}

		_, err = client.ImageVersion.UpdateOneID(imageVersionId).
			SetAzureSubscriptionID(azureSubscriptionId).
			Save(ctx)
		if err != nil {
			return fmt.Errorf("failed to update image version with assigned subscription")
		}

		successfullyAssigned = true
		return nil
	})
	if txErr != nil {
		return false, txErr
	}

	return successfullyAssigned, nil
}

func sqlPredicateSubscriptionHasFreeSlots(s *entsql.Selector) {
	s.Where(
		entsql.ColumnsLT(s.C(azuresubscription.FieldImageVersionsCount), s.C(azuresubscription.FieldImageVersionsLimit)),
	)
}
