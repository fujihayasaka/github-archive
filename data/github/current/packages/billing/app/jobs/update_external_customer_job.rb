# typed: strict
# frozen_string_literal: true

class UpdateExternalCustomerJob < BillingJob

  include GitHub::Billing::ZuoraRateLimitHandler
  queue_as :billing

  discard_on ActiveRecord::RecordNotFound

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, UpdateExternalCustomerJob)

    zuora_rate_limit_handler(self, error)
  end

  # Public: Update one BillingTransaction's statuses with data from correlating external billing vendor
  sig { params(customer: Customer).void }
  def perform(customer)
    # We need to check that they only have one customer account associated
    # because it's possible that multiple users are attached to the same external customer.
    # If they have more than one user, we cannot determine (yet) if the current user is the one
    # that should be updating the customer info.
    # Ignore that if the customer is associated with a business
    customer.update_external_account_name if customer.customer_accounts.one? || customer.business.present?
  end
end
