# typed: strict
# frozen_string_literal: true

module Billing
  class RetryFailedPaymentJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler
    include GitHub::Memoizer

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing

    sig { returns(T.nilable(Customer)) }
    attr_reader :customer

    MAX_PAYMENT_RETRY_ATTEMPTS = T.let(::User::BillingDependency::BILLING_ATTEMPTS_LIMIT, Integer)

    (Billing::Zuora::RETRYABLE_ERRORS + Billing::Braintree::RETRYABLE_ERRORS).each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, RetryFailedPaymentJob)

      zuora_rate_limit_handler(self, error)
    end

    before_enqueue do |job|
      customer = job.arguments.first
      job_status = Billing::JobStatus.create(id: self.class.job_id(customer), state: "queued")
    end

    # Track the job status as it is performed
    # The job status will not exist if the job is called with perform_now
    around_perform do |job, block|
      customer = job.arguments.first
      if job_status = Billing::JobStatus.find(self.class.job_id(customer))
        job_status.track { block.call }
      else
        block.call
      end
    end

    sig { returns(String) }
    def self.prefix
      "retry-collect-payment"
    end

    sig { params(customer: Customer).returns(String) }
    def self.job_id(customer)
      "#{prefix}-customer-#{customer.id}"
    end

    sig { params(customer: Customer).returns(T.nilable(JobStatus)) }
    def self.status(customer)
      Billing::JobStatus.find(job_id(customer))
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def self.currently_retrying?(customer)
      job_status = status(customer)
      return false unless job_status

      !job_status.finished?
    end

    sig { params(customer: Customer).void }
    def perform(customer)
      @customer = T.let(customer, T.nilable(Customer))
      return unless billable_entity = customer.billable_owner
      return unless billable_entity.dunning?
      return if billable_entity.disabled?
      return unless can_retry_payment?
      return unless customer.payment_method&.valid_payment_token?
      return unless payment_token = customer.payment_method&.payment_token
      return unless payment_to_retry = latest_failed_payment(customer)

      invoices = payment_to_retry.invoices
      payment_gateway = payment_to_retry.gateway
      payment = Billing::Zuora::Payment.create(origin: self.class.name.to_s, customer:, comment: "Created by RetryFailedPaymentJob", payment_token:, invoices:, payment_gateway:)

      result = payment.status != "Processed" ? GitHub::Billing::Result.failure(payment.gateway_response) : GitHub::Billing::Result.success
      # The billing attempt can be incremented if the payment is declined, via the payment decline code
      current_billing_attempt = retry_count + 1

      GitHub.dogstats.increment("billing.retry_failed_payment_job.create_payment",
        tags: ["billing_attempt:#{current_billing_attempt}", "payment_gateway:#{payment_gateway}",
          "success:#{result.success?}", "declined:#{result.declined?}"])
    end

    private

    sig { params(billable_owner: Billing::Types::Account).returns(T.nilable(Billing::BillingTransaction)) }
    def latest_failed_transaction(billable_owner)
      billable_owner.billing_transactions.unsuccessful_payment_collection.descending.first
    end

    sig { params(customer: Customer).returns(T.nilable(Billing::Zuora::Payment)) }
    def latest_failed_payment(customer)
      billable_owner = T.must(customer.billable_owner)
      # This gets the most recent transaction failed paid transaction
      # For now we only allow the user to pay off the most recent failed transaction
      transaction = latest_failed_transaction(billable_owner)
      return unless transaction
      platform_transaction_id = transaction.platform_transaction_id
      Billing::Zuora::Payment.find(platform_transaction_id)
    end

    sig { returns(Integer) }
    memoize def retry_count
      customer&.billable_owner&.billing_attempts || 0
    end

    sig { returns(T::Boolean) }
    def can_retry_payment?
      retry_count < MAX_PAYMENT_RETRY_ATTEMPTS
    end
  end
end
