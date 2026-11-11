# typed: strict
# frozen_string_literal: true

module Licensing
  class SyncCustomerLicensesInLicensifyJob < ApplicationJob
    include ::Licensing::Licensify

    retry_on_dirty_exit

    queue_as :licensify_customer_update

    RETRYABLE_ERRORS = T.let(
      [
        Net::OpenTimeout,
        Net::ReadTimeout,
        Licensing::Licensify::Error,
      ].freeze,
      T::Array[Object],
    )

    RETRYABLE_ERRORS.each do |error_class|
      retry_on error_class, wait: :polynomially_longer, attempts: 10 do |_job, error|
        GitHub.dogstats.increment("licensify.sync_customer_licenses_job_failed", tags: [
          "error:#{error.class.name.underscore.parameterize}"
        ])
        Failbot.report(error)
      end
    end

    sig { params(customer_id: Integer).void }
    def perform(customer_id)
      return unless GitHub.billing_enabled?

      sync_request = ::Licensify::Services::V1::SyncCustomerRequest.new(
        customerId: customer_id,
      )

      sync_response = licensify_client.sync_customer(sync_request)

      if sync_response.error.present?
        raise ::Licensing::Licensify::Error, sync_response.error
      end
    end
  end
end
