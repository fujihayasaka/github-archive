# typed: strict
# frozen_string_literal: true

module Sponsorship::InstrumentationDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  include Instrumentation::Model

  requires_ancestor { Sponsorship }

  # Public: Cancellation reason used for Hydro event SponsorshipCancelRequest
  HYDRO_CANCELLATION_REASONS = T.let([
    :UNKNOWN,
    :SPONSOR_INITIATED,
    :STAFF_INITIATED,
    :SPAMMY_SPONSOR,
    :EXPIRED_SPONSORSHIP,
    :BLOCKED_USER,
    :SPONSOR_TRADE_COMPLIANCE_FLAGGED,
    :BANNED_LISTING,
    :DISABLED_LISTING,
    :UNPUBLISHED_LISTING,
    :PAYPAL_DEPRECATION,
    :PATREON_ACCOUNT_DISCONNECTED,
    :BILLABLE_ROLLBACK,
    :INVOICED_SPONSOR_CREATED,
    :BUSINESS_REVOKED_ORG_SPONSOR_ACCESS,
  ].freeze, T::Array[Symbol])

  # Public: Create audit log and Hydro events to indicate sponsorship has been started.
  # Service classes for creating sponsorships (Sponsors::CreateSponsorship and children) are responsible
  # for calling this method.
  #
  # This only indicates that a sponsorship has been created/started, and not that it has been paid,
  # which is handled by #instrument_payment_complete.
  #
  # via_bulk_sponsorship - Boolean indicating whether this payment was made as part of many other sponsorships
  #                        being started at once, e.g., via our Bulk Sponsorship tool to add multiple one-time
  #                        payments to many sponsorables
  sig { params(via_bulk_sponsorship: T::Boolean).void }
  def instrument_sponsorship_start(via_bulk_sponsorship: false)
    return unless active?

    # Used for audit log and Stratocaster (see config/instrumentation/stratocaster.rb)
    instrument :sponsor_sponsorship_create, actor: actor, prefix: :sponsors

    # Hydro (see config/instrumentation/hydro/subscriptions/sponsors.rb)
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_create",
      actor: actor,
      sponsorship: self,
      listing: sponsors_listing,
      tier: tier,
      matchable: matchable?,
      action: :CREATE,
      goal: active_goal,
      first_time_sponsor: first_time_sponsor?,
      first_time_sponsorable: first_time_sponsorable?,
      invoiced: manual_invoiced? || sponsors_invoiced?,
      listing_stafftools_metadata: sponsors_listing_stafftools_metadata,
      via_bulk_sponsorship: via_bulk_sponsorship,
      payment_source: patreon? ? :PATREON : :GITHUB,
    )
  end

  # Public: Create audit log and Hydro events to indicate payment has been received for this
  # sponsorship. This is triggered on the creation of a Billing::BillingTransaction::LineItem.
  # Also triggers a sponsorship webhook and the creation of a SponsorsActivity.
  #
  # tier_paid - SponsorsTier corresponding to this payment
  # via_bulk_sponsorship - Boolean indicating whether this payment was made as part of many other sponsorships
  #                        being started at once, e.g., via our Bulk Sponsorship tool to add multiple one-time
  #                        payments to many sponsorables
  sig { params(tier_paid: SponsorsTier, via_bulk_sponsorship: T::Boolean).void }
  def instrument_payment_complete(tier_paid:, via_bulk_sponsorship:)
    # Create audit log event, which triggers the creation of a sponsorship webhook
    # with action=created.
    payload = payment_complete_payload(tier_paid: tier_paid, via_bulk_sponsorship: via_bulk_sponsorship)
    instrument(:sponsor_sponsorship_payment_complete, **payload)

    # Hydro; creating this Hydro event triggers the creation of a new SponsorsActivity record
    # via SponsorshipPaymentCompleteProcessor
    GlobalInstrumenter.instrument("sponsors.sponsorship_payment_complete",
      sponsorship: self,
      actor: actor || sponsor,
      listing: sponsors_listing,
      tier: tier_paid,
      matchable: matchable?,
      goal: active_goal,
      first_time_sponsor: first_time_sponsor?,
      first_payment: payload[:first_payment],
      first_time_sponsorable: first_time_sponsorable?,
      invoiced: manual_invoiced? || sponsors_invoiced?,
      via_bulk_sponsorship: via_bulk_sponsorship,
      completed_at: Time.current,
      payment_source: patreon? ? :PATREON : :GITHUB,
    )

    check_active_goal_completion
  end

  sig { params(actor: T.nilable(User)).void }
  def instrument_cancel(actor:)
    self.actor = actor

    # Hydro; creating this Hydro event triggers the creation of a new SponsorsActivity record
    # via SponsorshipCancelProcessor
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_cancel",
      actor: actor,
      sponsorship: self,
      listing: sponsors_listing,
      tier: tier,
      action: :CANCEL,
      goal: active_goal,
      invoiced: manual_invoiced? || sponsors_invoiced?,
      listing_stafftools_metadata: sponsors_listing_stafftools_metadata,
      payment_source: patreon? ? :PATREON : :GITHUB,
    )

    # Audit log; creating the audit log event triggers the creation of a sponsorship webhook
    # with action=cancelled
    instrument :sponsor_sponsorship_cancel, actor: actor, prefix: :sponsors
  end

  sig do
    params(
      actor: T.nilable(User),
      pending_change_on: T.nilable(T.any(String, DateTime, Date, Time, ActiveSupport::TimeWithZone))
    ).void
  end
  def instrument_cancelling(actor:, pending_change_on:)
    self.actor = actor

    # Audit log
    instrument :sponsor_sponsorship_pending_cancellation,
      prefix: :sponsors,
      actor: actor,
      pending_change_on: pending_change_on
  end

  sig { params(reason: T.nilable(Symbol), force: T::Boolean, actor: T.nilable(User)).void }
  def instrument_cancel_request(reason:, force:, actor: nil)
    # We are only interested in "intentional" cancellations. These can only come
    # from recurring sponsorships because the one-time frequency is immediately set for expiration/cancellation.
    return unless recurring_payment? || manually_invoiced_consecutive_recurrence?

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsorship_cancel_request",
      sponsorship: self,
      tier: tier,
      listing: sponsors_listing,
      listing_stafftools_metadata: sponsors_listing_stafftools_metadata,
      actor: actor,
      sponsor: sponsor,
      sponsorable: sponsorable,
      reason: cancel_request_hydro_attribute_for(reason),
      forced: force,
    )
  end

  sig { params(actor: T.nilable(User), previous_tier: T.nilable(SponsorsTier)).void }
  def instrument_tier_change(actor:, previous_tier:)
    self.actor = actor

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_tier_change",
      actor: actor,
      sponsorship: self,
      listing: sponsors_listing,
      current_tier: tier,
      previous_tier: previous_tier,
      goal: active_goal
    )

    # Audit log
    instrument :sponsor_sponsorship_tier_change,
      actor: actor,
      previous_tier_id: previous_tier&.id,
      prefix: :sponsors
  end

  # Public: create an audit log entry for reactivating an inactive sponsorship.
  #         Used for sponsorships that were incorrectly cancelled and should be activated without collecting payment.
  #
  # actor - staff User who reactivated the sponsorship
  sig { params(actor: T.nilable(User)).void }
  def instrument_restoration(actor:)
    self.actor = actor
    staff_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
    payload = staff_actor.merge(prefix: :sponsors)
    instrument :sponsor_sponsorship_restore, payload
  end

  sig do
    params(
      actor: T.nilable(User),
      pending_subscription_item_change: T.nilable(Billing::PendingSubscriptionItemChange)
    ).void
  end
  def instrument_pending_tier_change(actor:, pending_subscription_item_change:)
    self.actor = actor

    # Audit log
    instrument :sponsor_sponsorship_pending_tier_change,
      prefix: :sponsors,
      actor: actor,
      pending_change_tier_id: pending_subscription_item_change&.subscribable&.id,
      pending_change_on: pending_subscription_item_change&.active_on
  end

  # Public: Emit a `github.sponsors.v1.SponsorshipPendingChange` Hydro event to indicate this sponsorship will be
  # changed.
  #
  # actor - User who initiated the change
  # old_tier - the previous SponsorsTier
  # new_tier - the new SponsorsTier, or nil to indicate a cancellation
  sig do
    params(
      actor: T.nilable(User),
      old_tier: T.nilable(SponsorsTier),
      new_tier: T.nilable(SponsorsTier)
    ).void
  end
  def instrument_pending_change(actor:, old_tier:, new_tier:)
    self.actor = actor

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_pending_change",
      actor: actor,
      sponsorship: self,
      listing: sponsors_listing,
      old_tier: old_tier,
      new_tier: new_tier,
      action: :CREATE,
      goal: active_goal,
    )
  end

  sig { params(actor: T.nilable(User), previous_sponsorship: T.nilable(Sponsorship)).void }
  def instrument_preference_change(actor:, previous_sponsorship:)
    self.actor = actor

    # Audit log
    instrument :sponsor_sponsorship_preference_change, actor: actor, prefix: :sponsors

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_preference_change",
      actor: actor,
      previous_sponsorship: previous_sponsorship,
      current_sponsorship: self,
      listing: sponsors_listing,
      tier: subscription_item&.subscribable
    )
  end

  sig { params(actor: T.nilable(User), previous_privacy_level: T.nilable(T.any(String, Symbol))).void }
  def instrument_privacy_level_change(actor:, previous_privacy_level:)
    self.actor = actor

    actor_hash = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      { actor: actor }
    end
    payload = actor_hash.merge(
      changes: { privacy_level: { from: previous_privacy_level } },
      prefix: :sponsors
    )

    # Audit log
    instrument :sponsor_sponsorship_edited, payload
  end

  sig { params(billing_line_items: T::Array[Billing::BillingTransaction::LineItem], reason: T.nilable(String)).void }
  def instrument_transfer_failure(billing_line_items:, reason:)
    first_line_item = billing_line_items.first
    stripe_account_id = first_line_item&.sponsors_stripe_transfer_account_id
    stripe_connect_account = Billing::StripeConnect::Account.find_by(stripe_account_id: stripe_account_id)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsorship_transfer_failure", {
      reason: reason,
      amount_in_cents: billing_line_items.map(&:amount_in_cents).sum,
      listing: sponsors_listing,
      sponsorship: self,
      stripe_account_id: stripe_account_id,
      stripe_connect_account: stripe_connect_account,
      billing_transaction_id: first_line_item&.billing_transaction_id,
    })

    GitHub.dogstats.increment("sponsors.transfer.failed")
  end

  private

  sig { void }
  def instrument_sponsorship_expire
    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsor_sponsorship_expire",
      sponsorship: self,
      listing: sponsors_listing,
      tier: tier,
      listing_stafftools_metadata: sponsors_listing_stafftools_metadata,
    )
  end

  sig { void }
  def instrument_cancellation
    # Doesn't make sense to create SponsorsActivity or webhooks that say a one-time payment was cancelled, since
    # one-time sponsorships are just "one and done" with no expectation of continuing payments after the first,
    # so don't trigger audit log or Hydro events for one-time sponsorship cancellations:
    if recurring_or_invoiced_payment?
      instrument_cancel(actor: actor)
    elsif one_time_payment?
      instrument_sponsorship_expire
    end
  end

  sig { params(reason: T.nilable(Symbol)).returns(Symbol) }
  def cancel_request_hydro_attribute_for(reason)
    return reason if reason.present? && HYDRO_CANCELLATION_REASONS.include?(reason)

    :UNKNOWN
  end

  sig { returns T::Boolean }
  def first_payment?
    paid_at.nil?
  end

  sig do
    params(tier_paid: SponsorsTier, via_bulk_sponsorship: T.nilable(T::Boolean)).returns(T::Hash[Symbol, T.untyped])
  end
  def payment_complete_payload(tier_paid:, via_bulk_sponsorship:)
    payload = {
      actor: actor || sponsor,
      first_payment: first_payment?,
      prefix: :sponsors,
      via_bulk_sponsorship: via_bulk_sponsorship,
    }

    if concurrent_payment?(tier_paid: tier_paid)
      # concurrent payments override tier information
      payload.merge!(
        is_concurrent_payment: true,
        first_payment: true,
        frequency: tier_paid.frequency,
        current_tier_id: tier_paid.id,
        current_tier_monthly_amount_in_cents: tier_paid.monthly_price_in_cents,
      )
    end

    payload
  end
end
