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
    mapped_keys = %w[id display_name source os_type architecture latest_version_size_gb image_versions total_versions_size versions_count latest_version state]
    custom_images = larger_runners_custom_images(entity)

    if exclude_deleting
      custom_images = custom_images.reject { |image| image.state == :Deleting }
    end

    custom_images = custom_images.map do |image|
      image_versions = query_versions ? get_transformed_image_versions_models(entity: entity, image: image) : []
      transformed_image = image.as_json(only: mapped_keys)
      transformed_image["state"] = transformed_image["state"].to_s.sub(/^ImageDefinition/, "")
      transformed_image.merge(image_versions: image_versions).transform_keys { |key| key.to_s.camelize(:lower) }
    end
    custom_images
  end

  def get_transformed_image_versions_models(entity:, image:)
    image_versions = Actions::ImageVersion.custom_image_versions_for_image_including_latest(entity, image_id: image&.id.to_i)
    image_versions.map do |image_version|
      image_version.as_json(only: %w[version state size state_details]).transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def get_custom_image(entity:, image_id:)
    Actions::Image.custom_image_for(entity, image_id: image_id)
  end

  def get_detailed_transformed_image_versions_models(entity:, image:)
    image_versions = Actions::ImageVersion.custom_image_versions_for_image(entity, image_id: image&.id.to_i)
    image_versions.map do |image_version|
      image_version.as_json(only: %w[version state state_details size last_used_on created_on]).transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def custom_image_in_use_by_runner?(entity, image_definition_id, image_version = nil)
    larger_runners = Actions::LargerRunner.larger_runners_for(entity: entity)

    # Select runners that are using the custom image
    larger_runners_matching_image = larger_runners.select do |pool|
      pool.image&.source == :Custom &&
      pool.image&.id == image_definition_id.to_s &&
      pool.state != :Deleting
    end

    # Early return: if no runners are using this image, it can be deleted
    return false if larger_runners_matching_image.empty?

    # If no specific image version is provided and there are runners using the image, it can't be deleted
    return true if image_version.nil?

    # Only call get_custom_image if there is a runner with version 'latest'
    has_latest_runner = larger_runners_matching_image.any? { |runner| runner.image&.version == "latest" }
    image_definition_latest_version = nil
    if has_latest_runner
      all_image_versions = custom_image_versions_for_image(entity, image_id: image_definition_id)
      image_definition_latest_version = all_image_versions.detect { |ver| ver.state == :Ready } ||
        all_image_versions.detect { |ver| ver.state == :Provisioning } ||
        all_image_versions.detect { |ver| ver.state == :Generating }
    end

    larger_runners_matching_image.any? do |runner|
      runner.image&.version == image_version ||
        (has_latest_runner && runner.image&.version == "latest" && image_definition_latest_version&.version == image_version)
    end
  end
end
