# typed: true
# frozen_string_literal: true

class SecretScanningBulkEnablementJob < ApplicationJob
  queue_as :secret_scanning_bulk_enablement
  retry_on_dirty_exit

  def perform(org:, actor:, config_name:, config_description:, include_private_repos:, enable_on_unattached_repos_with_conflict:)
    success = false
    started_at = GitHub::Dogstats.monotonic_time

    begin
      with_write do
        ::SecretScanning::BulkEnablementService.enable_all_secret_scanning(
          org,
          actor,
          config_name,
          config_description,
          include_private_repos: include_private_repos,
          enable_on_unattached_repos_with_conflict: enable_on_unattached_repos_with_conflict
        )
      end
      success = true
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      GitHub.dogstats.increment("secret_scanning.bulk_enablement.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("secret_scanning.bulk_enablement.duration", GitHub::Dogstats.duration(started_at))
    end
  end
end
