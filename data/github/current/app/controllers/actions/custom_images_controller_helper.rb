# typed: strict
# frozen_string_literal: true

module Actions::CustomImagesControllerHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunners::CustomImagesHelper

  sig do
    params(
      entity: T.any(Organization, Business),
      image_id: T.nilable(String),
      version: T.nilable(String),
      actor: User
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def delete_customer_image_version(entity:, image_id:, version:, actor:)
    image_definition_id = image_id&.to_i
    version = version || ""

    return { success: false, errors: ["Not found"], status: :not_found } unless image_definition_id.present?
    return { success: false, errors: ["Invalid version"], status: :not_found } unless valid_version_specifier?(version)

    image_used_error_message = "Failed to delete custom image version because it's currently used by at least one runner."

    if custom_image_in_use_by_runner?(entity, image_definition_id, version)
      return { success: false, errors: [image_used_error_message], status: :unprocessable_entity }
    end

    error_message = "Failed to delete custom image version."
    resp = HostedComputeIms::Twirp.customer_images_client.delete_customer_image_version(
      owner: entity,
      image_definition_id: image_definition_id,
      version: version
    )

    if resp.respond_to?(:call_succeeded?) && !resp.call_succeeded?
      { success: false, errors: [error_message], status: resp.status }
    else
      if entity.feature_flag_enabled?(:custom_images_audit_log_events, default: false)
        entity.instrument "delete_custom_image_version",
          actor: actor,
          image_definition_id: image_definition_id,
          version: version
      end
      { success: true, errors: [], status: :ok }
    end
  end

  sig do
    params(
      entity: T.any(Organization, Business),
      image_id: T.nilable(String),
      actor: User
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def delete_customer_image(entity:, image_id:, actor:)
    image_definition_id = image_id&.to_i
    return { success: false, errors: ["Not found"], status: :not_found } unless image_definition_id.present?

    image_used_error_message = "Failed to delete custom image because it's currently used by at least one runner."

    if custom_image_in_use_by_runner?(entity, image_definition_id)
      return { success: false, errors: [image_used_error_message], status: :unprocessable_entity }
    end

    error_message = "Failed to delete custom image."
    resp = HostedComputeIms::Twirp.customer_images_client.delete_customer_image_definition(
      owner: entity,
      image_definition_id: image_definition_id
    )

    if resp.respond_to?(:call_succeeded?) && !resp.call_succeeded?
      { success: false, errors: [error_message], status: resp.status }
    else
      if entity.feature_flag_enabled?(:custom_images_audit_log_events, default: false)
        entity.instrument "delete_custom_image",
          actor: actor,
          image_definition_id: image_definition_id
      end
      { success: true, errors: [], status: :ok }
    end
  end
end
