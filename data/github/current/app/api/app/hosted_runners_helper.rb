# typed: true
# frozen_string_literal: true

module Api::App::HostedRunnersHelper
  extend T::Helpers
  include ::Actions::LargerRunnersHelper

  requires_ancestor { Api::App }

  sig { params(entity: T.any(Organization, Business)).void }
  def confirm_api_enabled!(entity)
    deliver_error! 404, message: "GitHub hosted runners are not supported in this environment" unless GitHub.actions_larger_runners_enabled?
    type = entity.is_a?(Business) ? "enterprise" : "organization"
    deliver_error! 404, message: "GitHub hosted runners are not supported for this #{type}" unless entity.can_use_larger_runners? || entity.is_eligible_to_onboard_larger_runners?
  end

  sig { params(entity: T.any(Organization, Business), actor: User).void }
  def ensure_larger_runners_and_launch_ready!(entity:, actor:)
    ensure_larger_runners_onboarded!(entity: entity, actor: actor, this_entity: entity)
    ensure_tenant_exists!(entity: entity)
  end

  sig { params(entity: T.any(Organization, Business)).void }
  def ensure_tenant_exists!(entity:)
    if entity.is_a?(Organization)
      business = entity.business
      if business.present?
        result = Launch::Twirp.deployer_client.setup_tenant(business)
        raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
      end
    end

    result = Launch::Twirp.deployer_client.setup_tenant(entity)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  sig { params(entity: T.any(Organization, Business), actor: User, this_entity: T.any(Organization, Business)).void }
  def ensure_larger_runners_onboarded!(entity:, actor:, this_entity:)
    return if entity.can_use_larger_runners?

    if entity.is_eligible_to_onboard_larger_runners?
      entity.onboard_larger_runners(actor: actor)
    else
      deliver_error! 404
    end
  end

  sig { params(id: T.nilable(String), source: T.nilable(String), entity: T.any(Organization, Business)).returns(T.nilable(Actions::Image)) }
  def get_image_details_from_request(id:, source:, entity:)
    return nil if id.nil? || source.nil?
    case source
    when "github"
      Actions::Image.curated_images_for(entity).find { |i| i.id == id }
    when "partner"
      Actions::Image.marketplace_images_for(entity).find { |i| i.id == id }
    when "custom"
      return nil unless is_custom_images_enabled?(entity: entity)
      Actions::Image.custom_images_for(entity).find { |i| i.id.to_s == id.to_s }
    end
  end

  sig { params(image: T.any(NilClass, Actions::LargerRunner::ImageKey, GitHub::Launch::Services::Largerrunners::ImageKey), entity: T.any(Organization, Business)).returns(T.nilable(Actions::Image)) }
  def get_image_details(image:, entity:)
    return nil if image.nil?
    case image.source
    when :Curated
      Actions::Image.curated_images_for(entity).find { |i| i.id == image.id }
    when :Marketplace
      Actions::Image.marketplace_images_for(entity).find { |i| i.id == image.id }
    when :Custom
      return nil unless is_custom_images_enabled?(entity: entity)
      Actions::Image.custom_images_for(entity).find { |i| i.id.to_s == image.id.to_s }
    end
  end

  sig { params(machine_spec_id: String, entity: T.any(Organization, Business)).returns(T.nilable(Actions::MachineSpec)) }
  def get_machine_spec_details(machine_spec_id:, entity:)
    machine_specs = Actions::MachineSpec.machine_specs_for(entity)
    machine_specs.find { |i| i.id == machine_spec_id }
  end

  def validate_listing!(result)
    unless result
      Failbot.report(StandardError.new("no response from list"), launch_larger_runners: Launch::Twirp::larger_runners_client)
      deliver_error!(503, message: "Larger runners unavailable. Please try again later.")
    end
  end
end
