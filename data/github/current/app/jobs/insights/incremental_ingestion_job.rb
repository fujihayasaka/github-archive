# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class Insights::IncrementalIngestionJob < ApplicationJob
  retry_on_dirty_exit

  retry_on_recoverable_exceptions do |job, error|
    topic, entity_name, entity_id, source_time = job.arguments[0..3]
    job.report_error(error, topic, entity_name, entity_id, source_time)
  end

  exempt_from_tenant_context_requirement

  RETRYABLE_ERRORS = [
    GitHub::Restraint::UnableToLock,
    Redis::CommandError,
    Redis::CannotConnectError,
  ].freeze

  MAX_ATTEMPTS        = 50
  RETRY_WAIT          = 10.seconds
  MAX_CONCURRENT_JOBS = 50
  LOCK_TTL            = 1.hour

  retry_on(*RETRYABLE_ERRORS, wait: RETRY_WAIT, attempts: MAX_ATTEMPTS) do |job, error|
    topic, entity_name, entity_id, source_time = job.arguments[0..3]
    job.report_error(error, topic, entity_name, entity_id, source_time)
  end

  queue_as :insights_incremental_ingestion


  def perform(topic, entity_name, entity_id, job_scheduled_at, updated_at = nil, parent_entity = nil)
    # Intentionally left empty
  end

  def report_error(error, topic, entity_name, entity_id, source_time)
    GitHub.logger.error(
      "exception.message" => error.message,
      "gh.insights.tenant.id" => @tenant_id,
      "gh.insights.entity.name" => entity_name,
      "gh.insights.entity.id" => entity_id,
      "messaging.destination.name" => topic,
      "gh.insights.source.time" => source_time,
      "gh.retries.attempt.number" => executions,
    )
    GitHub.dogstats.increment("insights.incremental_ingestion.publish_error")
    Failbot.report(
      error,
      entity: entity_name,
      entity_id: entity_id,
      tenant_id: @tenant_id,
      insights_domain_event: topic)
  end
end
