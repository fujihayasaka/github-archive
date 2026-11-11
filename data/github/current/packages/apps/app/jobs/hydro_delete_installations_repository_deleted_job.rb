# typed: true
# frozen_string_literal: true

class HydroDeleteInstallationsRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_delete_installations_repository_deleted

  def perform
    # These events should be emitted before the repo is removed from the installations
    repository.instrument_repo_removed_from_installations

    # Queue background jobs to remove the repo from installations
    # REF: https://github.com/github/github/pull/221920
    installations = IntegrationInstallation.with_repository(repository)
    installations.each do |installation|
      IntegrationInstallationRepositoryRemovalJob.perform_later(
        installation, repository.id, entry_point: :hydro_message_handler_repo_removed_from_installations,
      )
    end
  end
end
