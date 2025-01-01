# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::LargerRunners::CustomImagesHelper
  include Actions::LargerRunnersHelper

  private

  sig { params(version_specifier: T::nilable(String)).returns(T::Boolean) }
  def valid_version_specifier?(version_specifier)
    # a valid version will be a three-part semver-style version string (with '0.0.0' invalid)
    !version_specifier.nil? && version_specifier.match?(/^(?!0\.0\.0$)\d+\.\d+\.\d+$/)
  end

  def get_transformed_custom_images_models(entity:, exclude_deleting: false, query_versions: true)
    mapped_keys = %w[id display_name source os_type architecture size_gb image_versions total_versions_size version_count latest_version state]
    custom_images = larger_runners_custom_images(entity)

    if exclude_deleting
      custom_images = custom_images.reject { |image| image.state == :Deleting }
    end

    custom_images = custom_images.map do |image|
      image_versions = query_versions ? get_transformed_image_versions_models(entity: entity, image: image) : []
      image.as_json(only: mapped_keys).merge(image_versions: image_versions).transform_keys { |key| key.to_s.camelize(:lower) }
    end

    custom_images
  end

  def get_transformed_image_versions_models(entity:, image:)
    image_versions = Actions::ImageVersion.custom_image_versions_for_image_including_latest(entity, image_id: image&.id.to_i)
    image_versions.map do |image_version|
      image_version.as_json(only: %w[version state failure_reason]).transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def get_custom_image(entity:, image_id:)
    Actions::Image.custom_image_for(entity, image_id: image_id)
  end

  def get_detailed_transformed_image_versions_models(entity:, image:)
    image_versions = Actions::ImageVersion.custom_image_versions_for_image(entity, image_id: image&.id.to_i)
    image_versions.map do |image_version|
      image_version.as_json(only: %w[version state failure_reason size last_used_on created_on]).transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end
end
