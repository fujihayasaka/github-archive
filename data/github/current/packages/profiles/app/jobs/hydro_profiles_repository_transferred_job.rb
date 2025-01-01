# typed: true
# frozen_string_literal: true

class HydroProfilesRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_profiles_repository_transferred

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    # If the old owner is an org, remove the repo from the old owner's pinned repositories.
    # Orgs are only allowed to pin their own public repos.
    if previous_owner.organization?
      with_write do
        ProfilePinner.unpin(repository, user: previous_owner, viewer: actor)
      end
    end
  end

  private

  sig { returns(User) }
  memoize def previous_owner
    User.find(message[:previous_owner][:id])
  end

  sig { returns(User) }
  memoize def actor
    User.find(message[:actor_id])
  end
end
