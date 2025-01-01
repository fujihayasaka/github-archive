package twirp

import (
	"context"
	"database/sql"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/models"
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

func (s *baseApiHandler) GetAndValidateImageDefinition(ctx context.Context,
	imageDefinitionId uint64,
	validator *twirpValidatorOptions,
) (*models.ImageDefinition, error) {
	imageDefinition, err := s.imageStore.GetImageDefinitionById(ctx, imageDefinitionId)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			s.logger.Info("image definition is not found by id",
				kvp.Uint64("image_definition_id", imageDefinitionId),
			)
			return nil, twirp.NotFound.Error("image definition is not found")
		} else {
			s.logger.ErrorWithReport("failed to get image definition", err, kvp.Uint64("image_definition_id", imageDefinitionId))
			return nil, twirp.Internal.Error("failed to get image definition")
		}
	}

	if validator != nil {
		if validator.shouldValidateType {
			if _, err := s.ValidateImageDefinitionType(imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidateOwner {
			if _, err := s.ValidateImageDefinitionOwner(imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidateEnabled {
			if _, err := s.ValidateEnabledImageDefinition(ctx, imageDefinition, validator); err != nil {
				return nil, err
			}
		}

		if validator.shouldValidatePointer {
			if _, err := s.ValidateImageDefinitionPointer(imageDefinition, validator); err != nil {
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
	imageVersion, err := s.imageStore.GetImageVersionByDefinitionIdAndVersion(ctx, imageDefinitionId, version)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			s.logger.Info("image version is not found by image definition id and version",
				kvp.Uint64("image_definition_id", imageDefinitionId),
				kvp.String("image_version", version),
			)
			return nil, twirp.NotFound.Error("image version is not found")
		} else {
			s.logger.ErrorWithReport("failed to get image version", err, kvp.Uint64("image_definition_id", imageDefinitionId))
			return nil, twirp.Internal.Error("failed to get image version")
		}
	}

	if validator != nil {
		if validator.shouldValidateEnabled {
			if _, err := s.ValidateEnabledImageVersion(imageVersion); err != nil {
				return nil, err
			}
		}
	}

	return imageVersion, nil
}

func (s *baseApiHandler) ValidateImageDefinitionPointer(imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if !validator.allowPointer && imageDefinition.PointsToImageDefinitionId != nil {
		s.logger.Info("image definition pointer is not allowed",
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.Uint64("image_definition_points_to", *imageDefinition.PointsToImageDefinitionId),
		)

		return nil, twirp.InvalidArgument.Error("image definition pointer is not allowed for this operation")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateEnabledImageDefinition(ctx context.Context, imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if !isCuratedImageDefinitionEnabledForActor(ctx, imageDefinition, validator.enabledForActor) {
		s.logger.Info("image definition is disabled",
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.Bool("image_definition_enabled", imageDefinition.Enabled),
		)

		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateImageDefinitionType(imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if imageDefinition.ImageType != validator.expectedImageType {
		s.logger.Info("image definition has incorrect image type",
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.String("image_definition_type", string(imageDefinition.ImageType)),
			kvp.String("expected_type", string(validator.expectedImageType)),
		)

		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateImageDefinitionOwner(imageDefinition *models.ImageDefinition, validator *twirpValidatorOptions) (*models.ImageDefinition, error) {
	if imageDefinition.OwnerId != validator.expectedOwnerId {
		s.logger.Info("image definition has incorrect owner",
			kvp.Uint64("image_definition_id", imageDefinition.Id),
			kvp.String("image_definition_owner", imageDefinition.OwnerId),
			kvp.String("expected_owner", validator.expectedOwnerId),
		)

		return nil, twirp.NotFound.Error("image definition is not found")
	}

	return imageDefinition, nil
}

func (s *baseApiHandler) ValidateEnabledImageVersion(imageVersion *models.ImageVersion) (*models.ImageVersion, error) {
	if !imageVersion.Enabled {
		s.logger.Info("image version is disabled",
			kvp.Uint64("image_definition_id", imageVersion.ImageDefinitionId),
			kvp.String("image_version", imageVersion.Version),
			kvp.Bool("image_version_enabled", imageVersion.Enabled),
		)

		return nil, twirp.NotFound.Error("image version is not found")
	}

	return imageVersion, nil
}

func isCuratedImageDefinitionEnabledForActor(ctx context.Context, imageDefinition *models.ImageDefinition, actor *sharedapi.Actor) bool {
	if imageDefinition.FeatureFlag != nil && *imageDefinition.FeatureFlag != "" {
		return featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag(*imageDefinition.FeatureFlag), mapApiToActor(actor))
	}
	return imageDefinition.Enabled
}
