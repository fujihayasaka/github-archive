# typed: strict
# frozen_string_literal: true

class SecretScanningSelectiveEnablementJob < ApplicationJob
  queue_as :secret_scanning_selective_enablement
  retry_on_dirty_exit

  sig do
    params(
      org: Organization,
      actor: User,
      config_name: String,
      config_description: String,
      repo_ids: T::Array[Integer]
    ).void
  end
  def perform(org:, actor:, config_name:, config_description:, repo_ids:)
    if repo_ids.empty?
      GitHub.logger.info("SecretScanningSelectiveEnablementJob: no repo_ids provided; nothing to do")
      return
    end

    success = false
    started_at = GitHub::Dogstats.monotonic_time

    begin
      with_write do
        ::SecretScanning::BulkEnablementService.enable_secret_scanning_for_repositories(
          org,
          actor,
          repo_ids,
          config_name,
          config_description
        )
      end

      success = true
    rescue StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      GitHub.dogstats.increment("secret_scanning.selective_enablement.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("secret_scanning.selective_enablement.duration", GitHub::Dogstats.duration(started_at))
    end
  end
end
