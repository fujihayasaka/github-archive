# typed: strict
# frozen_string_literal: true

class Businesses::Actions::Policies::RunnerPoliciesComponent < ApplicationComponent
  include ::Actions::LargerRunnersHelper

  sig { params(entity: Business).void }
  def initialize(entity:)
    @entity = entity
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end

  sig { returns(T::Boolean) }
  def show_custom_images_policies?
    is_custom_images_enabled?(entity: @entity)
  end

  sig { returns(T::Boolean) }
  def show_custom_images_retention_policy?
    is_custom_images_enabled?(entity: @entity) && is_custom_images_retention_policy_feature_enabled?(entity: @entity)
  end

  sig { returns(T::Boolean) }
  def show_standard_hosted_runners_toggle?
    FeatureFlag.vexi.enabled?(:actions_macos_in_runner_groups_enabled, @entity, default: false)
  end

  sig { returns(T::Boolean) }
  def standard_hosted_runners_disabled?
    limits = Launch::Twirp.concurrency_limit_overrides_client.get_concurrency_limit_overrides(owner: @entity)
    limits[:total] == 0
  rescue StandardError
    false
  end
end
