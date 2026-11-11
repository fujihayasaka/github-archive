# typed: true
# frozen_string_literal: true

class MassInstallAutomaticIntegrationsJob < InstallAutomaticIntegrationsJob
  TIME_TO_INSTALL_KEY = "mass_apps_installations:mean_time_to_install_ms"

  queue_as :mass_install_automatic_integrations

  def perform(target_id, integration_id, trigger_id, repo_ids = INSTALL_ON_ALL_REPOS, options = {})
    IntegrationInstallation.throttle do
      PendingAutomaticInstallation.throttle do
        super
      end
    end
  end

  private

  def track_time_to_install(integration, mean_time_to_install_ms)
    GitHub.legacy_redis.set(TIME_TO_INSTALL_KEY, mean_time_to_install_ms)

    super
  end
end
