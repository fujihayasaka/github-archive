# typed: strict
# frozen_string_literal: true

class CodeScanningBulkEnablementJob < ApplicationJob
  queue_as :code_scanning_bulk_enablement
  retry_on_dirty_exit

  sig do
    params(
      org: Organization,
      actor: User,
      config_name: String,
      config_description: String,
      enable_on_unattached_repos_with_conflict: T::Boolean,
    ).void
  end
  def perform(org:, actor:, config_name:, config_description:, enable_on_unattached_repos_with_conflict:)
    success = false
    started_at = GitHub::Dogstats.monotonic_time

    begin
      with_write do
        ::CodeScanning::BulkEnablementService.enable_code_scanning_for_all_configs(
          org,
          actor,
          config_name,
          config_description,
          enable_on_unattached_repos_with_conflict: enable_on_unattached_repos_with_conflict,
        )
      end
      success = true
    rescue StandardError => e
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      GitHub.dogstats.increment("code_scanning.bulk_enablement.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("code_scanning.bulk_enablement.duration", GitHub::Dogstats.duration(started_at))
    end
  end
end
