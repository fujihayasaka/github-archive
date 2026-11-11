# typed: true
# frozen_string_literal: true

class Actions::LargerRunnersOnboardingInfoComponent < ApplicationComponent
  def initialize(owner:)
    @owner = owner
  end

  def is_larger_runners_onboarded?
    @owner.is_larger_runners_onboarded?
  end

  def is_eligible_to_onboard_larger_runners?
    @owner.is_eligible_to_onboard_larger_runners?
  end

  def owner_host_id
    return "" if owner_tenant_info.nil?

    owner_tenant_info.tenant_id
  end

  def owner_runner_scale_unit
    return "" if owner_tenant_info.nil?

    scale_unit_url = owner_tenant_info.runner_scale_unit

    match = scale_unit_url.match /https?:\/\/([^\.]+)\./
    return scale_unit_url if match.nil? || match[1].nil?

    match[1]
  end

  memoize def owner_tenant_info
    begin
      return nil unless is_larger_runners_onboarded?

      resp = Launch::Twirp::larger_runners_client.get_tenant_info(@owner)
      return nil unless resp.call_succeeded?

      resp.value
    end
  end

  memoize def allow_managing_beta_features?
    begin
      @owner.is_larger_runners_onboarded? && @owner.can_use_larger_runners?
    end
  end

  memoize def beta_features
    begin
      return [] unless allow_managing_beta_features?

      [
        {
          title: "Image Generation",
          note: "Enables base images for image generation and allows making VM snapshot",
          feature_name: "image-generation",
        }
      ].map do |feature|
        feature_state = beta_features_states.find { |f| f.name == feature[:feature_name] }
        {
          **feature,
          feature_state_found: feature_state.present?,
          enabled_for_user: feature_state&.enabled_for_user,
          enabled_globally: feature_state&.enabled_globally
        }
      end
    end
  end

  def onboard_larger_runners_form_url
    if @owner.is_a?(Business)
      return onboard_larger_runners_stafftools_actions_path(@owner)
    end

    stafftools_actions_onboard_larger_runners_path(@owner)
  end

  def larger_runners_beta_features_form_url
    if @owner.is_a?(Business)
      return larger_runners_manage_beta_features_stafftools_actions_path(@owner)
    end

    stafftools_actions_larger_runners_manage_beta_features_path(@owner)
  end

  private

  memoize def beta_features_states
    begin
      larger_runners_service_response = Launch::Twirp::larger_runners_client.list_beta_features(@owner)
      larger_runners_beta_features = larger_runners_service_response.call_succeeded? ? larger_runners_service_response.value.features : []
    end
  end
end
