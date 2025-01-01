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
    is_custom_images_enabled?(entity: @entity) && is_custom_images_policy_feature_enabled?(entity: @entity)
  end
end
