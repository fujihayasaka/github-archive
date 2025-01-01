# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class BusinessOrganizationBillingJob < BillingJob
  RETRYABLE_ERRORS = T.let([
    ActiveRecord::RecordNotUnique,
    Braintree::UnexpectedError,
    Faraday::ConnectionFailed,
    Faraday::SSLError,
    Faraday::TimeoutError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    ActiveRecord::ConnectionFailed,
    WaitForReplication::DataUnavailable
  ].freeze, T::Array[T.class_of(StandardError)])

  discard_on(StandardError) do |_job, error|
    Failbot.report(error)
  end

  RETRYABLE_ERRORS.each do |retryable|
    retry_on(retryable, wait: :polynomially_longer, attempts: 7) do |_job, error|
      Failbot.report(error)
    end
  end

  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 5 do |_job, error|
    Failbot.report(error)
  end

  resolve_tenant_context do |business, _|
    business
  end

  sig { params(business: Business, org: Organization).void }
  def perform(business, org)
    return unless org.business == business

    with_write do
      lock!(business, org) do
        business.migrate_organization_to_business_billing(org)
      end
    end
  end

  private

  sig { params(business: Business, organization: Organization, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def lock!(business, organization, &block)
    lock_key = business.business_organization_billing_sync_key(organization)

    restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 1.minute) do
      yield
    end
  end

  sig { returns(GitHub::Restraint) }
  def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end
end
