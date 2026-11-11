# typed: true
# frozen_string_literal: true

class UninstallIntegrationInstallationJob < ApplicationJob
  queue_as :uninstall_integration_installation
  retry_on_dirty_exit

  def perform(actor_id, installation_id, staff_actor: false)
    actor = User.find_by(id: actor_id) || User.ghost

    if (installation = IntegrationInstallation.find_by(id: installation_id))
      if IntegrationInstallation.target_locked_for_deletion?(installation)
        GitHub.dogstats.increment("uninstall_integration_installation_job.target_locked_for_deletion")
        return
      end

      installation.uninstall(actor: actor, staff_actor: staff_actor)
    end
  end
end
