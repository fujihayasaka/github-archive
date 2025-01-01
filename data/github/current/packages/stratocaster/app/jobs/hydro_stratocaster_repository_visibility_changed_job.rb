# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/visibility_changed_pb"

class HydroStratocasterRepositoryVisibilityChangedJob < Repositories::RepositoryHydroMessageJob
  include Stratocaster::Domain::Provider

  queue_as :hydro_stratocaster_repository_visibility_changed

  retry_on_dirty_exit

  # Public: Handle Repository VisibilityChanged events
  sig { void }
  def perform
    return unless payload.new_visibility == Repository::PRIVATE_VISIBILITY.upcase.to_sym

    with_write do
      stratocaster_domain.drop_repo_events(repository)
    end
  end

  private

  sig { returns(Hydro::Schemas::Github::Repositories::V1::VisibilityChanged) }
  def payload
    Hydro::Schemas::Github::Repositories::V1::VisibilityChanged.new(message)
  end
end
