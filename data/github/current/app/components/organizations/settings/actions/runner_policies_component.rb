# typed: strict
# frozen_string_literal: true
class Organizations::Settings::Actions::RunnerPoliciesComponent < ApplicationComponent

  sig { params(entity: Organization).void }
  def initialize(entity:)
    @organization = entity
  end

  sig { returns(T::Boolean) }
  def render?
    @organization.can_write_organization_runners_and_runner_groups?(current_user)
  end
end
