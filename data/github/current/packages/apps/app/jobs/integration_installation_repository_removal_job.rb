# typed: true
# frozen_string_literal: true

class IntegrationInstallationRepositoryRemovalJob < ApplicationJob
  queue_as :integration_installation_repository_removal
  retry_on_dirty_exit

  # Discard the job if the installation is deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(installation, repository_id = nil, entry_point: Permissions::Service::EntryPoint.unknown)
    # Even if we endup uninstalling, lets clear the cache permissions before perfoming any repo removal.
    installation.clear_cached_permissions

    if can_be_uninstalled_automatically?(installation)
      userish     = installation.target || User.ghost
      uninstaller = userish.organization? ? userish.admins.first : userish

      if IntegrationInstallation.target_locked_for_deletion?(installation)
        GitHub.dogstats.increment("uninstall_integration_installation_job.target_locked_for_deletion")
        return
      end

      installation.uninstall(actor: uninstaller)
    else
      if repository_id
        ActiveRecord::Base.connected_to(role: :writing) do
          Permissions::Service.revoke_permissions_granted_on_subject(
            actor_id: installation.ability_id,
            actor_type: installation.ability_type,
            subject_id: repository_id,
            subject_types: Repository::Resources.individual_type_prefixed_subject_types,
            entry_point: entry_point,
          )
        end
      end
      UpdateIntegrationInstallationRateLimitJob.perform_later(installation.id)
    end
  end

  private

  # Internal: Can this IntegrationInstallation record be uninstalled
  # without user intervention?
  #
  # Returns a Boolean.
  def can_be_uninstalled_automatically?(installation)
    # If it's installed on the target User/Organization
    # we don't want to uninstall since repository selection isn't needed.
    return false if installation.installed_on_all_repositories?

    # If there are organization permissions we
    # don't want to uninstall
    return false unless installation.repository_permissions_only?

    # Ensure there are no repositories
    # remaining on the installation
    installation.repositories.none?
  end
end
