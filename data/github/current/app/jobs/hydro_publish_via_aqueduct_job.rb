# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroPublishViaAqueductJob < ApplicationJob
  queue_as :hydro_publish_via_aqueduct
  retry_on_dirty_exit

  class HydroPublishError < StandardError; end
  # Number of retry attempts for publishing to Hydro
  MAX_RETRY_ATTEMPTS = 8
  retry_on HydroPublishError, wait: :polynomially_longer, attempts: MAX_RETRY_ATTEMPTS

  def perform(payload, schema:, partition_key: nil, **options)
    final_attempt = executions == (MAX_RETRY_ATTEMPTS - 1) # 8 attempts total (0-7)

    begin
      result = GitHub.sync_hydro_publisher.publish(payload, schema:, partition_key:, **options)

      if result.success?
        record_metric(schema, success: true, final_attempt: final_attempt)
      else
        record_metric(schema, success: false, final_attempt: final_attempt)

        error = result.error
        message = error.respond_to?(:message) ? error.message : error.to_s
        original_exception = error.respond_to?(:original_exception) ? error.original_exception : nil

        if original_exception
          message = "#{message}; original exception: #{original_exception.class}: #{original_exception.message}"
        end

        raise HydroPublishError, "Failed to publish to Hydro: #{message}"
      end
    rescue => e
      record_metric(schema, success: false, final_attempt: final_attempt)
      raise e
    end
  end

  private

  def record_metric(schema, success:, final_attempt:)
    tags = [
      "schema:#{schema}",
      "success:#{success}",
      "final_attempt:#{final_attempt}"
    ]

    GitHub.dogstats.increment("hydro.aqueduct_job.publish", tags: tags)
  end
end
