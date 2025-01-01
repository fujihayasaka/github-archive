# typed: true
# frozen_string_literal: true

class HydroProfilesRepositoryVisibilityJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig

  queue_as :hydro_profiles_repository_visibility

  retry_on_dirty_exit

  sig { void }
  def perform
    return unless repository.private?

    with_write do
      ProfilePin.for_repository(repository).destroy_all
    end
  end
end
