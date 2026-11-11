# typed: true
# frozen_string_literal: true

# Automatically screens and processes a Business Startups application after form submission.
# Gated by the :gfs_auto_approval feature flag.
#
# Performs automated screening checks (eligibility, duplicate detection, domain-email alignment,
# abuse rate limiting) and either accepts or rejects the application.
# Emits Hydro events and sends notification emails on status transitions.
#
# Supports a dry-run mode (via `:gfs_approval_dry_run` feature flag)
# that runs the full screening pipeline and logs the decision without mutating application state.
class BusinessStartupsApplicationProcessingJob < ApplicationJob
  queue_as :business_startups_application_processing

  retry_on_dirty_exit
  retry_on ActiveRecord::RecordNotFound, wait: 5.seconds, attempts: 3

  sig { params(business_startups_program_id: Integer).void }
  def perform(business_startups_program_id:)
    application = BusinessStartupsProgram.find(business_startups_program_id)

    # Safety check: only process applications in "processing" state
    return unless application.application_status_processing?

    # Feature flag gate: if disabled, leave in processing for manual stafftools review
    return unless FeatureFlag.vexi.enabled?(:gfs_auto_approval, default: false)

    rejection_reason = BusinessStartupsProgram::Screening.call(application)

    with_write do
      decision = case rejection_reason
      when nil
        accept_application!(application)
        "accept"
      when BusinessStartupsProgram::Screening::REJECTION_DOMAIN_EMAIL_MISMATCH,
           BusinessStartupsProgram::Screening::REJECTION_MISSING_CRUNCHBASE
        set_pending_review_for_application!(application, rejection_reason)
        "pending_review"
      else
        reject_application!(application, rejection_reason)
        "reject"
      end

      GitHub.logger.info(
        "[GFS] Auto-processing decision",
        application_id: application.id,
        business_id: application.business_id,
        decision: decision,
        dry_run: dry_run?,
      )
    end
  end

  private

  sig { params(application: BusinessStartupsProgram, rejection_reason: T.untyped).void }
  def set_pending_review_for_application!(application, rejection_reason)
    return if dry_run?

    application.set_pending_review!(
      rejection_reason: rejection_reason,
      actor: User.ghost,
    )
  end

  DEFAULT_CREDIT_AMOUNT = "$10000.00"
  DEFAULT_CREDIT_DURATION_MONTHS = 12

  sig { returns(T::Boolean) }
  def dry_run?
    FeatureFlag.vexi.enabled?(:gfs_approval_dry_run, default: false)
  end

  sig { params(application: BusinessStartupsProgram).void }
  def accept_application!(application)
    return if dry_run?

    application.accept!(actor: User.ghost)

    GlobalInstrumenter.instrument("business_startups_program.accepted", {
      application: application,
      business: application.business,
      actor: User.ghost,
    })

    # Apply billing credit before sending email so failures can be caught
    credit_result = apply_billing_credit(application)

    unless credit_result[:success]
      # Roll back to pending_review for manual stafftools intervention
      application.set_pending_review!(
        rejection_reason: "billing_credit_failed",
        actor: User.ghost,
      )
      GitHub.logger.error("[GFS] Billing credit failed for application #{application.id}: #{credit_result[:error_message]}")
      GitHub.dogstats.increment(
        "business_startups.billing_credit.failed",
        tags: ["partner_id:#{application.application_data&.dig("partner_id")}"],
      )
      return
    end

    GitHub.dogstats.increment(
      "business_startups.billing_credit.applied",
      tags: ["partner_id:#{application.application_data&.dig("partner_id")}"],
    )

    BusinessStartupsApplicationMailer.acceptance_email(application).deliver_later

    GitHub.dogstats.increment(
      "business_startups.application_processing.accepted",
    )
  end

  sig { params(application: BusinessStartupsProgram).returns(T::Hash[Symbol, T.untyped]) }
  def apply_billing_credit(application)
    business = application.business

    unless business&.customer.present?
      return { success: false, error_message: "business has no billing customer" }
    end

    amount = Billing::Money.parse(DEFAULT_CREDIT_AMOUNT)
    start_date = Time.current
    end_date = start_date + DEFAULT_CREDIT_DURATION_MONTHS.months

    application.apply_billing_credit(amount: amount, start_date: start_date, end_date: end_date)
  end

  sig { params(application: BusinessStartupsProgram, rejection_reason: T.nilable(String)).void }
  def reject_application!(application, rejection_reason)
    return if dry_run?

    resolved_reason = rejection_reason || "screening_failed"

    application.reject!(
      rejection_reason: resolved_reason,
      actor: User.ghost
    )

    GlobalInstrumenter.instrument("business_startups_program.rejected", {
      application: application,
      business: application.business,
      actor: User.ghost,
      rejection_reason: resolved_reason,
    })

    BusinessStartupsApplicationMailer.rejection_email(application).deliver_later

    GitHub.dogstats.increment(
      "business_startups.application_processing.rejected",
      tags: [
        "reason:#{resolved_reason}",
      ]
    )
  end
end
