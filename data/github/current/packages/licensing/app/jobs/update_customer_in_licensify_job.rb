# typed: strict
# frozen_string_literal: true

class UpdateCustomerInLicensifyJob < ApplicationJob
  include ::Licensing::Licensify

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :licensify_customer_update

  class NoBillableOwnerError < StandardError; end

  RETRYABLE_ERRORS = T.let(
    [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Licensing::Licensify::Error,
      NoBillableOwnerError
    ].freeze,
    T::Array[Object],
  )

  RETRYABLE_ERRORS.each do |error_class|
    retry_on error_class, wait: :polynomially_longer, attempts: 10 do |_job, error|
      GitHub.dogstats.increment("licensify.update_customer_in_licensify_job_failed", tags: [
        "error:#{error.class.name.underscore.parameterize}"
      ])
      Failbot.report(error)
    end
  end

  retry_on GitHub::Restraint::UnableToLock, wait: 30.seconds, attempts: 5

  sig { params(customer_id: Integer).void }
  def perform(customer_id)
    return unless GitHub.billing_enabled?

    customer = Customer.find_by(id: customer_id)
    return unless customer.present?

    if customer.billable_owner.nil?
      GitHub.dogstats.increment("licensify.update_customer_in_licensify_no_billable_owner_error")
      raise NoBillableOwnerError, "Customer #{customer.id} has no billable owner (yet)."
    end
    if customer.billable_owner.instance_of?(User)
      GitHub.dogstats.increment("licensify.update_customer_in_licensify_job_skipped")
      return
    end

    lock_key = "#{self.class.name}-#{customer.id}"
    concurrent_jobs = 1
    lock_ttl = 1.minute

    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
      customer_payload = customer.to_licensify_customer_payload
      licensify_res = licensify_client.upsert_customer(customer: customer_payload)

      if licensify_res.error.present?
        raise Licensing::Licensify::Error, licensify_res.error
      end
    end
  end
end
