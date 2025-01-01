# typed: true
# frozen_string_literal: true

class HydroOrganizationCollaboratorUpdateOnRepoChangeJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig

  queue_as :hydro_organization_collaborator_update_on_repo_change

  # Public: process a Hydro message
  sig { void }
  def perform
    repository.update_collaborator_cache
  end
end
