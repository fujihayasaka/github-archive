# rubocop:todo GitHub/EnforcePackageAppStructure
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

  # Toggles the auto_pay status of the account according to their SDN status
  sig { params(id: Integer).void }
  def perform(id)
    @errors = []
    @profile = T.let(AccountScreeningProfile.find_by(id: id), T.nilable(AccountScreeningProfile))
    return GitHub.logger.error("Unable to find AccountScreeningProfile for billing toggle", "gh.account_screening_profile.id": id) unless owner = @profile&.owner

    if @profile.disable_autopay_status?
      to_restricted_status(owner)
      @profile.business&.organizations&.each { |org| to_restricted_status(org) }
      @profile.user&.orgs_linked_to_screening_record&.each { |org| to_restricted_status(org) }
    elsif @profile.can_enable_autopay?
      to_enabled_status(owner)
      @profile.business&.organizations&.each { |org| to_enabled_status(org) }
      @profile.user&.orgs_linked_to_screening_record&.each { |org| to_enabled_status(org) }
    end
  end

  private

  sig { params(owner: Billing::Types::Account).void }
  def to_restricted_status(owner)
    errors = T.must(@errors)

    with_write { owner.disable_auto_pay!(:trade_controls) }
    errors << "auto pay failed to disable" if owner.customer&.zuora? && !owner.autopay_disabled_by_trade_controls?

    owner.suspend_billing
    success = true
    success = with_write { owner.cancel_all_sponsorships(actor: User.staff_user, reason: :SPONSOR_TRADE_COMPLIANCE_FLAGGED) } unless T.must(@profile).temporary_status?
    errors << "Sponsorship(s) failed to cancel" unless success

    log_any_errors(owner)
  end

  sig { params(owner: Billing::Types::Account).void }
  def to_enabled_status(owner)
    errors = T.must(@errors)

    with_write { owner.enable_auto_pay!(:trade_controls) }
    errors << "auto pay failed to enable" if owner.autopay_disabled_by_trade_controls?

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
end
