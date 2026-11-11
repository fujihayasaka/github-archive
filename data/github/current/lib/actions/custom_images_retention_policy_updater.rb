# typed: strict
# frozen_string_literal: true

class Actions::CustomImagesRetentionPolicyUpdater

  sig { params(options: T.untyped).void }
  def self.perform(**options)
    new(**T.unsafe(options)).perform
  end

  sig { params(entity: T.any(::Business, ::Organization), image_versions_per_image_limit: Integer, image_versions_max_age_limit: Integer, image_versions_unused_age_limit: Integer).returns(T::Boolean) }
  def self.valid_inputs?(entity:, image_versions_per_image_limit:, image_versions_max_age_limit:, image_versions_unused_age_limit:)
    image_versions_per_image_limit.between?(Configurable::ActionsCustomImagesRetentionSettings::VERSIONS_PER_IMAGE_LIMIT_MIN,
                                  entity.max_allowed_custom_image_versions_per_image_limit) &&
    image_versions_max_age_limit.between?(Configurable::ActionsCustomImagesRetentionSettings::VERSION_MAX_AGE_LIMIT_MIN,
                      entity.max_allowed_custom_image_version_max_age_limit) &&
    image_versions_unused_age_limit.between?(Configurable::ActionsCustomImagesRetentionSettings::VERSION_UNUSED_AGE_LIMIT_MIN,
                              entity.max_allowed_custom_image_version_unused_age_limit)
  end

  sig { params(entity: T.any(::Business, ::Organization), image_versions_per_image_limit: Integer, image_versions_max_age_limit: Integer, image_versions_unused_age_limit: Integer, actor: ::User).void }
  def initialize(entity:, image_versions_per_image_limit:, image_versions_max_age_limit:, image_versions_unused_age_limit:, actor:)
    @entity = entity
    @image_versions_per_image_limit = image_versions_per_image_limit
    @image_versions_max_age_limit = image_versions_max_age_limit
    @image_versions_unused_age_limit = image_versions_unused_age_limit
    @actor = actor

    # Store old values for instrumentation
    @old_image_versions_per_image_limit = T.let(entity.custom_image_versions_per_image_limit, T.nilable(Integer))
    @old_image_versions_max_age_limit = T.let(entity.custom_image_version_max_age_limit, T.nilable(Integer))
    @old_image_versions_unused_age_limit = T.let(entity.custom_image_version_unused_age_limit, T.nilable(Integer))
  end

  sig { void }
  def perform
    update_settings
    instrument_changes
  end

  private

  sig { void }
  def update_settings
    @entity.set_custom_image_versions_per_image_limit(limit: @image_versions_per_image_limit, actor: @actor)
    @entity.set_custom_image_version_max_age_limit(limit: @image_versions_max_age_limit, actor: @actor)
    @entity.set_custom_image_version_unused_age_limit(limit: @image_versions_unused_age_limit, actor: @actor)
  end

  sig { void }
  def instrument_changes
    return unless settings_changed?

    @entity.instrument "update_custom_images_retention_policy",
      actor: @actor,
      old_image_versions_per_image_limit: @old_image_versions_per_image_limit,
      new_image_versions_per_image_limit: @image_versions_per_image_limit,
      old_image_versions_max_age_limit: @old_image_versions_max_age_limit,
      new_image_versions_max_age_limit: @image_versions_max_age_limit,
      old_image_versions_unused_age_limit: @old_image_versions_unused_age_limit,
      new_image_versions_unused_age_limit: @image_versions_unused_age_limit
  end

  sig { returns(T::Boolean) }
  def settings_changed?
    @entity.custom_image_versions_per_image_limit != @old_image_versions_per_image_limit ||
      @entity.custom_image_version_max_age_limit != @old_image_versions_max_age_limit ||
      @entity.custom_image_version_unused_age_limit != @old_image_versions_unused_age_limit
  end
end
