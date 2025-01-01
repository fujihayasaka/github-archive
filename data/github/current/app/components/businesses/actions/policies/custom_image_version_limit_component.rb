# typed: true
# frozen_string_literal: true

class Businesses::Actions::Policies::CustomImageVersionLimitComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests, ViewComponent/ComponentsHaveUnitTests
  def initialize(entity:, action:)
    @entity = entity
    @update_custom_image_retention_policy_path = action
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end

  memoize def image_version_max_age_limit
    @entity.custom_image_version_max_age_limit
  end

  memoize def image_version_unused_age_limit
    @entity.custom_image_version_unused_age_limit
  end

  memoize def image_versions_per_image_limit
    @entity.custom_image_versions_per_image_limit
  end

  def image_versions_per_image_limit_min
    Configurable::ActionsCustomImagesRetentionSettings::VERSIONS_PER_IMAGE_LIMIT_MIN
  end

  def image_version_unused_age_limit_min
    Configurable::ActionsCustomImagesRetentionSettings::VERSION_UNUSED_AGE_LIMIT_MIN
  end

  def image_version_max_age_limit_min
    Configurable::ActionsCustomImagesRetentionSettings::VERSION_MAX_AGE_LIMIT_MIN
  end

  def image_versions_per_image_limit_max
    Configurable::ActionsCustomImagesRetentionSettings::VERSIONS_PER_IMAGE_LIMIT_MAX
  end

  def image_version_unused_age_limit_max
    Configurable::ActionsCustomImagesRetentionSettings::VERSION_UNUSED_AGE_LIMIT_MAX
  end

  def image_version_max_age_limit_max
    Configurable::ActionsCustomImagesRetentionSettings::VERSION_MAX_AGE_LIMIT_MAX
  end
end
