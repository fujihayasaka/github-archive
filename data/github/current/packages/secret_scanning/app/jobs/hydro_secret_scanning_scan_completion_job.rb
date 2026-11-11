# typed: strict
# frozen_string_literal: true

# HydroSecretScanningScanCompletionJob is a no-op job that validates the new hydro event flow
# for secret scanning scan completion webhook processing. It consumes messages and emits metrics,
# but does not queue any webhook deliveries.
#
# Message topic: token_scanning_service.v0.ScanCompleteEventWebhook
# (same proto as ScanCompleteEvent — uses hydro.schemas.token_scanning_service.v0.ScanCompleteEvent)
#
# Replaces: GitHub::StreamProcessors::SecretScanning::ScanCompletionProcessor
class HydroSecretScanningScanCompletionJob < HydroMessageJob
  include RepositoryHydroMessageJobTenantContext

  queue_as :hydro_secret_scanning_scan_completion

  retry_on_dirty_exit
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  sig { void }
  def perform
    start = Time.now
    success = false

    begin
      # No-op: validate message can be consumed without processing.
      # Future PRs will add actual webhook delivery logic.
      GitHub.logger.info(
        "No-op: ScanCompleteEvent message received",
        "code.namespace": self.class.name,
        "gh.repo.id": message[:repository_id],
        "topic": headers["topic"]
      )
      success = true
    ensure
      duration_ms = (Time.now - start) * 1000
      tags = [
        "topic:#{headers["topic"]}",
        "job:scan_completion",
        "source:hydro_job",
        "success:#{success}",
        "noop:true",
        "bridge:true",
      ]

      GitHub.dogstats.distribution("secret_scanning.webhook_processor.duration", duration_ms, tags: tags)
      since_requested_ms = (Time.now - Time.at(timestamp)).to_f * 1000
      GitHub.dogstats.distribution("secret_scanning.webhook_processor.duration.since_requested", since_requested_ms, tags: tags)
    end
  end

  sig { override.returns(Integer) }
  def repository_id
    message[:repository_id]
  end
end
