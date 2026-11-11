# typed: strict
# frozen_string_literal: true

class CodeScanningSelectiveEnablementJob < ApplicationJob
  queue_as :code_scanning_selective_enablement
  retry_on_dirty_exit

  sig do
    params(
      org: Organization,
      actor: User,
      config_name: String,
      config_description: String,
      repo_ids: T::Array[Integer],
    ).void
  end
  def perform(org:, actor:, config_name:, config_description:, repo_ids:)
    if repo_ids.empty?
      GitHub.logger.info("CodeScanningSelectiveEnablementJob: no repo_ids provided; nothing to do")
      return
    end

    success = false
    started_at = GitHub::Dogstats.monotonic_time

    begin
      with_write do
        ::CodeScanning::BulkEnablementService.enable_code_scanning_for_repositories(
          org,
          actor,
          repo_ids,
          config_name,
          config_description,
        )
      end

      success = true
    rescue StandardError => e
      Failbot.report(e, {
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      GitHub.dogstats.increment("code_scanning.selective_enablement.complete", tags: ["success:#{success}"])
      GitHub.dogstats.distribution("code_scanning.selective_enablement.duration", GitHub::Dogstats.duration(started_at))
    end
  end
end
