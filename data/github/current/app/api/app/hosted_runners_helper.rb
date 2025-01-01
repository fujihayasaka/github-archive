# typed: true
# frozen_string_literal: true

module Api::App::HostedRunnersHelper
  extend T::Helpers

  requires_ancestor { Api::App }

  sig { params(entity: T.any(Organization, Business)).void }
  def ensure_tenant_and_confirm_api_enabled!(entity)
    deliver_error! 404 if !entity.feature_enabled?(:actions_hosted_runners_api)
    deliver_error! 404 unless GitHub.actions_larger_runners_enabled?

    ensure_larger_runners_onboarded!(entity: entity, actor: current_user, this_entity: entity)
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
