# typed: strict
# frozen_string_literal: true

class Organizations::Settings::Actions::RunnerPoliciesComponent < ApplicationComponent
  include ::Actions::LargerRunnersHelper

  sig { params(entity: Organization).void }
  def initialize(entity:)
    @organization = entity
  end

  sig { returns(T::Boolean) }
  def render?
    @organization.can_write_organization_runners_and_runner_groups?(current_user)
  end

  sig { returns(T::Boolean) }
  def show_custom_images_policies?
    is_custom_images_enabled?(entity: @organization)
  end

  sig { returns(T::Boolean) }
  def show_custom_images_retention_policy?
    is_custom_images_enabled?(entity: @organization) && is_custom_images_retention_policy_feature_enabled?(entity: @organization)
  end

  sig { returns(T::Boolean) }
  def show_standard_hosted_runners_toggle?
    business = @organization.business
    if business
      FeatureFlag.vexi.enabled?(:actions_macos_in_runner_groups_enabled, @organization, business, default: false)
    else
      FeatureFlag.vexi.enabled?(:actions_macos_in_runner_groups_enabled, @organization, default: false)
    end
  end

  sig { returns(T::Boolean) }
  def standard_hosted_runners_disabled?
    limits = Launch::Twirp.concurrency_limit_overrides_client.get_concurrency_limit_overrides(owner: @organization)
    limits[:total] == 0
  rescue StandardError
    false
  end
end
