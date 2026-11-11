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
    is_custom_images_enabled?(entity: @organization) && is_custom_images_policy_feature_enabled?(entity: @organization)
  end

  sig { returns(T::Boolean) }
  def show_custom_images_retention_policy?
    is_custom_images_enabled?(entity: @organization) && is_custom_images_retention_policy_feature_enabled?(entity: @organization)
  end
end
