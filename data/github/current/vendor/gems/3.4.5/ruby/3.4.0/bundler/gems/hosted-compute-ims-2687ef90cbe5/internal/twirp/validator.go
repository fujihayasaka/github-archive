package twirp

import (
	"context"
	"database/sql"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/twitchtv/twirp"
)

type twirpValidatorOptions struct {
	shouldValidateEnabled bool
	enabledForActor       *sharedapi.Actor
	shouldValidateType    bool
	expectedImageType     models.ImageType
	shouldValidateOwner   bool
	expectedOwnerId       string
	shouldValidatePointer bool
	allowPointer          bool
}

type validationOption func(*twirpValidatorOptions)

func newTwirpValidator(opts ...validationOption) *twirpValidatorOptions {
	v := &twirpValidatorOptions{}

	for _, opt := range opts {
		opt(v)
	}

	return v
}

func allowPointerValidation(allowPointer bool) validationOption {
	return func(v *twirpValidatorOptions) {
		v.shouldValidatePointer = true
		v.allowPointer = allowPointer
	}
}

func withEnabledImageDefinitionForActorValidation(actor *sharedapi.Actor) validationOption {
	return func(v *twirpValidatorOptions) {
		v.shouldValidateEnabled = true
		v.enabledForActor = actor
	}
}

func withEnabledImageVersionValidation() validationOption {
	return func(v *twirpValidatorOptions) {
		v.shouldValidateEnabled = true
	}
}

func withImageTypeValidation(expectedImageType models.ImageType) validationOption {
	return func(v *twirpValidatorOptions) {
		v.shouldValidateType = true
		v.expectedImageType = expectedImageType
	}
}

func withImageOwnerValidation(expectedOwnerId string) validationOption {
	return func(v *twirpValidatorOptions) {
		v.shouldValidateOwner = true
		v.expectedOwnerId = expectedOwnerId
	}
}

func (s *baseApiHandler) GetAndValidateImageDefinition(
	ctx context.Context,
	imageDefinitionId uint64,
	validator *twirpValidatorOptions,
) (*models.ImageDefinition, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_definition_id", imageDefinitionId))

	imageDefinition, err := s.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			logger.Info(ctx, "image definition is not found by id")
			return nil, twirp.NotFound.Error("image definition is not found")
		} else {
			logger.ErrorWithReport(ctx, "failed to get image definition", err)
			return nil, twirp.Internal.Error("failed to get image definition")
		}
	}

	if validator != nil {
		if validator.shouldValidateType {
			if _, err := s.ValidateImageDefinitionType(ctx, imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidateOwner {
			if _, err := s.ValidateImageDefinitionOwner(ctx, imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidateEnabled {
			if _, err := s.ValidateEnabledImageDefinition(ctx, imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidatePointer {
			if _, err := s.ValidateImageDefinitionPointer(ctx, imageDefinition, validator); err != nil {
				return nil, err
			}
		}
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) GetAndValidateImageVersionByImageDefinitionIdAndVersion(ctx context.Context,
	imageDefinitionId uint64,
	version string,
	validator *twirpValidatorOptions,
) (*models.ImageVersion, error) {
	ctx = stash.WithLoggingFields(ctx,
		kvp.Uint64("image_definition_id", imageDefinitionId),
		kvp.String("image_version", version),
	)

	imageVersion, err := s.imageStore.GetImageVersionByDefinitionIdAndVersion(ctx, imageDefinitionId, version)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			logger.Info(ctx, "image version is not found by image definition id and version")
			return nil, twirp.NotFound.Error("image version is not found")
		} else {
			logger.ErrorWithReport(ctx, "failed to get image version", err)
			return nil, twirp.Internal.Error("failed to get image version")
		}
	}

	if validator != nil {
		if validator.shouldValidateEnabled {
			if _, err := s.ValidateEnabledImageVersion(ctx, imageVersion); err != nil {
				return nil, err
			}
		}
	}

	return imageVersion, nil
}

func (s *baseApiHandler) ValidateImageDefinitionPointer(ctx context.Context, imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if !validator.allowPointer && imageDefinition.PointsToImageDefinitionId != nil {
		logger.Info(ctx, "image definition pointer is not allowed", kvp.Uint64("image_definition_points_to", *imageDefinition.PointsToImageDefinitionId))

		return nil, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateEnabledImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	enabled := s.isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, validator.enabledForActor)
	if !enabled {
		logger.Info(ctx, "image definition is disabled", kvp.Bool("image_definition_enabled", imageDefinition.Enabled))
		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateImageDefinitionType(ctx context.Context, imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if imageDefinition.ImageType != validator.expectedImageType {
		logger.Info(ctx, "image definition has incorrect image type",
			kvp.String("image_definition_type", string(imageDefinition.ImageType)),
			kvp.String("expected_type", string(validator.expectedImageType)),
		)

		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateImageDefinitionOwner(ctx context.Context, imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if imageDefinition.OwnerId != validator.expectedOwnerId {
		logger.Info(ctx, "image definition has incorrect owner",
			kvp.String("image_definition_owner", imageDefinition.OwnerId),
			kvp.String("expected_owner", validator.expectedOwnerId),
		)

		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateEnabledImageVersion(ctx context.Context, imageVersion *models.ImageVersion) (*models.ImageVersion, error) {
	if !imageVersion.Enabled {
		logger.Info(ctx, "image version is disabled", kvp.Bool("image_version_enabled", imageVersion.Enabled))

		return nil, twirp.NotFound.Error("image version is not found")
	}

	return imageVersion, nil
}
