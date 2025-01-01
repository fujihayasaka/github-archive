# typed: strict
# frozen_string_literal: true

module Actions::CustomImagesControllerHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunners::CustomImagesHelper

  sig do
    params(
      entity: T.any(Organization, Business),
      image_id: T.nilable(String),
      version: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def delete_customer_image_version(entity:, image_id:, version:)
    image_definition_id = image_id&.to_i
    version = version || ""

    return { success: false, errors: ["Not found"], status: :not_found } unless image_definition_id.present?
    return { success: false, errors: ["Invalid version"], status: :not_found } unless valid_version_specifier?(version)

    image_used_error_message = "Failed to delete custom image version because it's currently used by at least one runner."

    if is_custom_image_usage_by_runner_validation_enabled?(entity: entity)
      if custom_image_in_use_by_runner?(entity, image_definition_id, version)
        return { success: false, errors: [image_used_error_message], status: :unprocessable_entity }
      end
    end

    error_message = "Failed to delete custom image version."
    resp = nil

    if is_larger_runners_use_custom_images_from_ims_enabled?(entity: entity)
      resp = HostedComputeIms::Twirp.customer_images_client.delete_customer_image_version(
        owner: entity,
        image_definition_id: image_definition_id,
        version: version
      )
    else
      resp = Launch::Twirp::larger_runners_client.delete_image_version(entity, image_definition_id: image_definition_id, image_version: version)
      if !resp.call_succeeded? && resp.options&.fetch(:message, nil).to_s.include?("because it's currently referenced by at least one pool")
        error_message = image_used_error_message
      end
    end

    if resp.respond_to?(:call_succeeded?) && !resp.call_succeeded?
      { success: false, errors: [error_message], status: resp.status }
    else
      { success: true, errors: [], status: :ok }
    end
  end

  sig do
    params(
      entity: T.any(Organization, Business),
      image_id: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def delete_customer_image(entity:, image_id:)
    image_definition_id = image_id&.to_i
    return { success: false, errors: ["Not found"], status: :not_found } unless image_definition_id.present?

    image_used_error_message = "Failed to delete custom image because it's currently used by at least one runner."

    if is_custom_image_usage_by_runner_validation_enabled?(entity: entity)
      if custom_image_in_use_by_runner?(entity, image_definition_id)
        return { success: false, errors: [image_used_error_message], status: :unprocessable_entity }
      end
    end

    error_message = "Failed to delete custom image."
    resp = nil

    if is_larger_runners_use_custom_images_from_ims_enabled?(entity: entity)
      resp = HostedComputeIms::Twirp.customer_images_client.delete_customer_image_definition(
        owner: entity,
        image_definition_id: image_definition_id
      )
    else
      resp = Launch::Twirp::larger_runners_client.delete_image_definition(entity, image_definition_id: image_definition_id)
      if !resp.call_succeeded? && resp.options&.fetch(:message, nil).to_s.include?("because it's currently referenced by at least one pool")
        error_message = image_used_error_message
      end
    end

    if resp.respond_to?(:call_succeeded?) && !resp.call_succeeded?
      { success: false, errors: [error_message], status: resp.status }
    else
      { success: true, errors: [], status: :ok }
    end
  end
end
