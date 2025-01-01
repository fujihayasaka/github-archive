# typed: true
# frozen_string_literal: true

module Billing
  class DeadLetterQueueClearJob < BillingJob
    extend T::Sig

    TIME_LIMIT = 3.minutes
    queue_as :billing

    sig { params(queue_name: String, number_of_jobs_to_clear: Integer).void }
    def perform(queue_name:, number_of_jobs_to_clear:)
      GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
        ack_count = 0
        while ack_count < number_of_jobs_to_clear
          job = aqueduct_client.receive_job(queues: [queue_name], timeout: 1, bypass_pausing: true)
          if job[:job_id].present?
            aqueduct_client.ack_job(queue: queue_name, success: true, job_id: job[:job_id])
            ack_count += 1
          end
        end

        if timer.expired? && (ack_count < number_of_jobs_to_clear)
          GitHub.dogstats.count("billing.dead_letter_queue_clear_job.timeout_with_jobs_remaining", number_of_jobs_to_clear - ack_count)
          self.class.perform_later(queue_name: queue_name, number_of_jobs_to_clear: number_of_jobs_to_clear - ack_count)
        end
      end
    end

    def aqueduct_client
      GitHub.build_aqueduct_client(
        app: "billing-platform-#{Rails.env}",
        api_key: GitHub.aqueduct_billing_platform_api_key,
        api_key_version: GitHub.aqueduct_billing_platform_api_key_version,
      )
    end
  end
end
