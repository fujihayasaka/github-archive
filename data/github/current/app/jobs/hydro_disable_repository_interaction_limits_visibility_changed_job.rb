# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroDisableRepositoryInteractionLimitsVisibilityChangedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_disable_repository_interaction_limits_visibility_changed

  def perform
    return unless GitHub.interaction_limits_enabled? && repository

    ActiveRecord::Base.connected_to(role: :writing) do
      repository.disable_interaction_limits
    end
  end
end
