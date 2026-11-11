# typed: strict
# frozen_string_literal: true

class TradeControls::Sdn::BillingChangesJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :trade_screening
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  sig { returns(T.nilable(T::Array[String])) }
  attr_accessor :errors

  class BillingChangeError < StandardError; end

  RETRYABLE_ERRORS = T.let([
    ActiveRecord::RecordNotUnique,
    ActiveRecord::RecordNotFound,
    Freno::Error, # All things Freno
    *Resiliency::Response::UnavailableExceptions, # Recoverable exceptions
  ].freeze, T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |error|
    retry_on error, wait: :polynomially_longer, attempts: 10 do |_job, error|
      Failbot.report(error)
    end
  end

  retry_on WaitForReplication::DataUnavailable, wait: :polynomially_longer, attempts: :unlimited

  Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  retry_on(BillingChangeError, wait: :polynomially_longer, attempts: 5) do |_job, error|
    Failbot.report(error)
  end

  retry_on(GitHub::Restraint::UnableToLock, wait: :polynomially_longer) do |_job, error|
    Failbot.report(error)
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, TradeControls::Sdn::BillingChangesJob)
    zuora_rate_limit_handler(self, error)
  end

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  VALID_ACCOUNT_TYPES = T.let(%w[User Business].freeze, T::Array[String])

  # Toggles the auto_pay status of the account according to their SDN status
  sig { params(account_id: Integer, account_type: String, expected_screening_status: T.nilable(String)).void }
  def perform(account_id:, account_type:, expected_screening_status: nil)
    @errors = []

    return GitHub.logger.error("Unsupported account_type for billing toggle", "gh.account_type": account_type) unless VALID_ACCOUNT_TYPES.include?(account_type)
    account = T.let(account_type.constantize.find_by(id: account_id), T.nilable(Billing::Types::Account))
    return GitHub.logger.error("Unable to find account for billing toggle", "gh.account_id": account_id, "gh.account_type": account_type) unless account

    # No profile (e.g., org unlinked from a flagged contact) — re-enable billing
    profile = account.trade_screening_record
    return to_enabled_status(account) unless profile.persisted?

    # We noticed there's a mismatch in the current screening status and the expected one when screening updates happen in quick succession.
    # Since the job acts on the current status (not the expected one), and a job will get enqueued for the new status, we just log and return.
    if expected_screening_status.present? && profile.msft_trade_screening_status != expected_screening_status
      GitHub.logger.warn("Screening status mismatch, skipping stale job",
        "gh.account_screening_profile.id": profile.id,
        "gh.expected_status": expected_screening_status,
        "gh.current_status": profile.msft_trade_screening_status,
        "gh.owner_id": account.id
      )
      return
    end

    if profile.disable_autopay_status?
      to_restricted_status(account, profile)
      account.organizations.each { |org| to_restricted_status(org, profile) } if account.is_a?(Business)
      account.orgs_linked_to_billing_contact.each { |org| to_restricted_status(org, profile) } if account.is_a?(User)
    elsif profile.can_enable_autopay?
      to_enabled_status(account)
      account.organizations.each { |org| to_enabled_status(org) } if account.is_a?(Business)
      account.orgs_linked_to_billing_contact.each { |org| to_enabled_status(org) } if account.is_a?(User)
    end
  end

  private

  sig { params(owner: Billing::Types::Account, profile: AccountScreeningProfile).void }
  def to_restricted_status(owner, profile)
    errors = T.must(@errors)

    with_write { owner.disable_auto_pay!(:trade_controls) } if !is_sales_serve_business?(owner)
    errors << "auto pay failed to disable" if owner.customer&.zuora? && !is_sales_serve_business?(owner) && !owner.autopay_disabled_by_trade_controls?

    owner.suspend_billing(zero_out_invoices: true)
    success = true
    success = with_write { owner.cancel_all_sponsorships(actor: User.staff_user, reason: :SPONSOR_TRADE_COMPLIANCE_FLAGGED) } unless profile.temporary_status?
    errors << "Sponsorship(s) failed to cancel" unless success

    log_any_errors(owner)
  end

  sig { params(owner: Billing::Types::Account).void }
  def to_enabled_status(owner)
    errors = T.must(@errors)

    with_write { owner.enable_auto_pay!(:trade_controls) } if !is_sales_serve_business?(owner)
    errors << "auto pay failed to enable" if !is_sales_serve_business?(owner) && owner.autopay_disabled_by_trade_controls?

    owner.resume_billing
    log_any_errors(owner)
  end

  sig { params(owner: Billing::Types::Account).void }
  def log_any_errors(owner)
    return if T.must(errors).empty?

    external_uuid = owner.trade_screening_record.external_uuid
    all_errors = T.must(errors).join(", ")
    raise BillingChangeError.new "#{all_errors}. Owner ID: #{owner.id}, external ID: #{external_uuid}"
  end

  sig { params(owner: Billing::Types::Account).returns(T::Boolean) }
  def is_sales_serve_business?(owner)
    !!(owner.business? && !owner.self_serve_payment?)
  end
end
