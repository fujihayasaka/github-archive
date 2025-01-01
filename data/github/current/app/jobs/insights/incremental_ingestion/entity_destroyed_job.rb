# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class Insights::IncrementalIngestion::EntityDestroyedJob < ApplicationJob
  retry_on_dirty_exit

  retry_on_recoverable_exceptions do |job, error|
    entity_name, payload, source_time = job.arguments[0..2]
    entity_id = payload[:message][:data]["id"]
    tenant_id = payload[:message][:insights_enterprise_entity_id]
    job.report_error(error, entity_name, entity_id, tenant_id, source_time)
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

  HYDRO_TOPIC = "insights.entity_destroyed".freeze

  retry_on(*RETRYABLE_ERRORS, wait: RETRY_WAIT, attempts: MAX_ATTEMPTS) do |job, error|
    entity_name, payload, source_time = job.arguments[0..2]
    entity_id = payload[:message][:data]["id"]
    tenant_id = payload[:message][:insights_enterprise_entity_id]
    job.report_error(error, entity_name, entity_id, tenant_id, source_time)
  end

  queue_as :insights_incremental_ingestion_entity_destroyed

  def restraint_lock_key(entity_name, entity_id)
    "#{entity_name}:#{entity_id}"
  end

  def perform(entity_name, payload, modified_time)
    entity_id = payload[:message][:data]["id"]
    tenant_id = payload[:message][:insights_enterprise_entity_id]

    restraint = GitHub::Restraint.new
    restraint.lock!(restraint_lock_key(entity_name, entity_id), MAX_CONCURRENT_JOBS, LOCK_TTL) do
      begin
        GlobalInstrumenter.instrument(HYDRO_TOPIC, payload)
        current_time = Time.now.utc
        # publish latency calculated and reported in seconds (since opstore stores updated timestamps at seconds resolution)
        publish_latency = (current_time - modified_time).round
        GitHub.dogstats.distribution("insights.incr_ingestion.publisher_latency", publish_latency, tags: ["topic:entity_deleted"])
        if publish_latency > 600
          GitHub.logger.info(
            "Insights Publisher Latency is High.",
            "gh.insights.publisher_latency" => publish_latency,
            "gh.insights.entity.modified_at" => modified_time,
            "gh.insights.event.time" => current_time,
            "gh.insights.tenant.id" => tenant_id,
            "gh.insights.entity.name" => entity_name,
            "gh.insights.entity.id" => entity_id,
          )
        end
      rescue *RETRYABLE_ERRORS, *Resiliency::Response::UnavailableExceptions => e
        GitHub.logger.error(
          "Failed to publish message to Hydro. Retrying.",
          "exception.message" => e.message,
          "gh.insights.tenant.id" => tenant_id,
          "gh.insights.entity.name" => entity_name,
          "gh.insights.entity.id" => entity_id,
          "messaging.destination.name" => HYDRO_TOPIC,
          "gh.insights.entity.modified_at" => modified_time,
        )
        raise
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        report_error(e, entity_name, entity_id, tenant_id, modified_time)
        raise
      end
    end
  end

  def report_error(error, entity_name, entity_id, tenant_id, source_time)
    GitHub.logger.error(
      "exception.message" => error.message,
      "gh.insights.tenant.id" => tenant_id,
      "gh.insights.entity.name" => entity_name,
      "gh.insights.entity.id" => entity_id,
      "messaging.destination.name" => HYDRO_TOPIC,
      "gh.insights.source.time" => source_time,
      "gh.retries.attempt_number" => executions,
    )
    GitHub.dogstats.increment("insights.incremental_ingestion.publish_error")
    Failbot.report(
      error,
      tenant_id: tenant_id,
      entity: entity_name,
      entity_id: entity_id,
      insights_domain_event: HYDRO_TOPIC)
  end
end
