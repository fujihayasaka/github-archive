# typed: true
# frozen_string_literal: true

# Background job for suspending/unsuspending integrations as part of Spamurai moderation actions.
# This job handles DSA (Digital Services Act) compliance instrumentation and should only be used
# by Spamurai for content moderation purposes. For general integration suspension needs,
# consider using the Integration model methods directly.
class SpamuraiSuspendIntegrationsJob < ApplicationJob
  queue_as :spam

  use_primaries ApplicationRecord::Domain::Integrations

  METRICS_PREFIX = "integrations.jobs.spamurai_suspend_integrations"
  DEFAULT_BATCH_SIZE = 50
  DEFAULT_SLEEP_SECONDS = 0.1
  MAX_INTEGRATION_IDS = 100

  def perform(integration_ids:, action:, actor_id:, reason: nil, dsa_required: true, content_formats: nil, source: nil, tos_reason: nil, batch_size: DEFAULT_BATCH_SIZE, sleep_duration: DEFAULT_SLEEP_SECONDS)
    GitHub.logger.with_named_tags(build_logging_context(action, actor_id, integration_ids, reason, dsa_required, content_formats, source, tos_reason)) do
      if integration_ids.empty?
        report_skip("no_integration_ids", action: action)
        return
      end

      if integration_ids.size > MAX_INTEGRATION_IDS
        report_skip("too_many_integration_ids", action: action,
          integration_ids_count: integration_ids.size,
          max_allowed: MAX_INTEGRATION_IDS)
        return
      end

      unless %w[suspend unsuspend].include?(action)
        report_skip("invalid_action", action: action, invalid_action: action)
        return
      end

      actor = User.find_by(id: actor_id)
      unless actor
        report_skip("actor_not_found", action: action, actor_id: actor_id)
        return
      end

      unless actor.site_admin?
        report_skip("insufficient_permissions", action: action, actor_login: actor.display_login)
        return
      end

      integrations = Integration.where(id: integration_ids)
      found_count = integrations.count

      if found_count == 0
        report_skip("no_integrations_found", action: action)
        return
      end

      if found_count < integration_ids.length
        GitHub.logger.warn("Some integrations not found",
          "requested_count" => integration_ids.length,
          "found_count" => found_count,
          "missing_ids" => (integration_ids - integrations.pluck(:id))
        )
      end

      success_count = 0
      error_count = 0

      integrations.find_in_batches(batch_size: batch_size).each_with_index do |batch, idx|
        batch.each do |integration|
          begin
            case action
            when "suspend"
              success = Integration.throttle_writes_with_retry(max_retry_count: 3) do
                integration.suspend(
                  actor: actor,
                  reason: reason
                )
              end

              if success
                # Handle DSA instrumentation in the job
                if dsa_required
                  GlobalInstrumenter.instrument "staff.suspend_integration", {
                    actor: actor,
                    integration: integration,
                    reason: reason,
                    tos_reason: tos_reason,
                    content_formats: content_formats,
                    source: source
                  }
                end
                success_count += 1
              else
                error_count += 1
                GitHub.logger.warn("Failed to suspend integration",
                  "integration_id" => integration.id,
                  "integration_slug" => integration.slug
                )
              end
            when "unsuspend"
              success = Integration.throttle_writes_with_retry(max_retry_count: 3) do
                integration.unsuspend(actor: actor)
              end

              if success
                success_count += 1
              else
                error_count += 1
                GitHub.logger.warn("Failed to unsuspend integration",
                  "integration_id" => integration.id,
                  "integration_slug" => integration.slug
                )
              end
            end
          rescue => e
            error_count += 1
            GitHub.logger.error("Exception during integration #{action}",
              "integration_id" => integration.id,
              "integration_slug" => integration.slug,
              "error" => e.message
            )
          end
        end

        GitHub.logger.info("Processed batch ##{idx} of integrations", {
          "batch_size" => batch.size,
          "progress_success_count" => success_count,
          "progress_error_count" => error_count
        })

        sleep(sleep_duration)
      end

      # Report completion
      GitHub.logger.info("SpamuraiSuspendIntegrationsJob completed",
        build_logging_context(action, actor_id, integration_ids, reason, dsa_required, content_formats, source, tos_reason).merge(
          "success_count" => success_count,
          "error_count" => error_count,
          "total_requested" => integration_ids.length
        )
      )

      # Emit metrics
      GitHub.dogstats.increment("#{METRICS_PREFIX}.completed", tags: stats_tags + ["action:#{action}"])
      GitHub.dogstats.histogram("#{METRICS_PREFIX}.success_count", success_count, tags: stats_tags + ["action:#{action}"])
      GitHub.dogstats.histogram("#{METRICS_PREFIX}.error_count", error_count, tags: stats_tags + ["action:#{action}"])
    end

  rescue => e
    GitHub.logger.error("SpamuraiSuspendIntegrationsJob failed",
      build_logging_context(action, actor_id, integration_ids, reason, dsa_required, content_formats, source, tos_reason).merge(
        "error" => e.message,
        "backtrace" => (e.backtrace || []).join("\n")
      )
    )

    GitHub.dogstats.increment("#{METRICS_PREFIX}.failed", tags: stats_tags + ["action:#{action}"])
    raise
  end

  private

  def build_logging_context(action = nil, actor_id = nil, integration_ids = nil, reason = nil, dsa_required = nil, content_formats = nil, source = nil, tos_reason = nil)
    {
      "job.class" => self.class.name,
      "job.queue" => queue_name,
      "job.action" => action,
      "job.actor_id" => actor_id,
      "job.integration_count" => integration_ids&.length || 0,
      "job.reason" => reason,
      "job.dsa_required" => dsa_required,
      "job.content_formats" => content_formats,
      "job.source" => source,
      "job.tos_reason" => tos_reason
    }
  end

  def stats_tags
    [
      "queue:#{queue_name}"
    ].compact
  end

  def report_skip(cause, action:, **additional_context)
    # Include basic job context for skip logging
    context = {
      "job.class" => self.class.name,
      "job.queue" => queue_name,
      "job.action" => action,
      "cause" => cause
    }.merge(additional_context)

    GitHub.logger.warn("SpamuraiSuspendIntegrationsJob skipped", context)
    GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: stats_tags + ["cause:#{cause}", "action:#{action}"])
  end
end
