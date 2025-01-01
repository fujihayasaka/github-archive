# typed: true
# frozen_string_literal: true

class HydroAppsRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_apps_repository_created

  def perform
    IntegrationInstallation.with_repository(repository).pluck(:id).each do |installation_id|
      UpdateIntegrationInstallationRateLimitJob.perform_later(installation_id)
    end
  end
end
