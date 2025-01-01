# typed: strict
# frozen_string_literal: true

require_relative "../sponsors/k_v"

module Organization::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  STRIPE_LOGIN = "stripe"
  PRIVATE_PREMIUM_SPONSORS = T.let([STRIPE_LOGIN].freeze, T::Array[String])
  SPONSORS_INVOICE_MIGRATION_TTL = T.let(8.hours, ActiveSupport::Duration)

  included do
    T.bind(self, T.class_of(Organization))

    has_one :organization_profile, dependent: :destroy
    accepts_nested_attributes_for :organization_profile, update_only: true

    has_one :sponsoring_linked_organization, through: :organization_profile, class_name: "Organization",
      disable_joins: true
    has_many :sponsors_invoiced_agreement_signatures, foreign_key: :organization_id, inverse_of: :organization

    # Public: Get organizations that are part of the Premium Sponsors (aka Sponsors for Companies) program. Includes
    # old-style manually handled invoiced orgs as well as new-style Zuora-based invoiced orgs.
    #
    # active_only - Boolean indicating whether only those who have active sponsorships should be returned
    scope :premium_sponsors, ->(active_only: false) do
      if active_only
        where(id: active_premium_sponsor_ids)
      else
        where(id: premium_sponsor_ids)
      end
    end

    # Public: Get organizations that are part of the Premium Sponsors (aka Sponsors for Companies) program. Only
    # includes new-style Zuora-based invoiced orgs.
    scope :zuora_based_premium_sponsors, -> { where(id: zuora_based_premium_sponsor_ids) }
  end

  class_methods do

    sig { params(org_ids: T.nilable(T::Array[Integer])).returns(T::Set[Integer]) }
    def zuora_based_premium_sponsor_ids(org_ids: nil)
      zuora_based_org_ids = CustomerAccount.sponsors_purpose.joins(:customer)
        .merge(Customer.sponsors_purpose).distinct
      zuora_based_org_ids = zuora_based_org_ids.where(user_id: org_ids) if org_ids
      zuora_based_org_ids.pluck(:user_id).to_set
    end

    # Public: Get IDs of organizations that are part of the Premium Sponsors (aka Sponsors for Companies) program.
    # Includes old-style manually handled invoiced orgs as well as new-style Zuora-based invoiced orgs. May include
    # past Premium Sponsors.
    #
    # org_ids - optional Array of Organization IDs to check; if given, only Premium Sponsors in this list will be
    #           returned
    #
    # Returns a Set of Integer database IDs.
    sig { params(org_ids: T.nilable(T::Array[Integer])).returns(T::Set[Integer]) }
    def premium_sponsor_ids(org_ids: nil)
      old_style_org_ids = InvoicedSponsorshipTransfer.completed.not_fully_reversed.distinct
      old_style_org_ids = old_style_org_ids.for_sponsor(org_ids) if org_ids
      old_style_org_ids = old_style_org_ids.pluck(:sponsor_id).to_set

      zuora_based_premium_sponsor_ids(org_ids: org_ids) | old_style_org_ids
    end

    sig { params(org_ids: T.nilable(T::Array[Integer])).returns(T::Set[Integer]) }
    def active_premium_sponsor_ids(org_ids: nil)
      sponsor_ids = premium_sponsor_ids(org_ids: org_ids)
      return Set.new if sponsor_ids.empty?
      Sponsorship.active.from_sponsor(sponsor_ids).distinct.pluck(:sponsor_id).to_set
    end
  end

  # Public: Indicates if this organization is part of the Premium Sponsors (aka Sponsors for Companies) program.
  sig { returns(T::Boolean) }
  def premium_sponsor?
    Organization.premium_sponsor_ids(org_ids: Array(id)).any?
  end

  sig { returns T::Boolean }
  def private_premium_sponsor?
    PRIVATE_PREMIUM_SPONSORS.include?(login)
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def sponsors_insights_accessible_by?(user)
    return false unless GitHub.sponsors_enabled? && GitHub.billing_enabled? && user&.persisted?
    @insights_accessible_by_user_id ||= T.let({}, T.nilable(T::Hash[Integer, T::Boolean]))
    user_id = T.must_because(user.id) { "#persisted? check ensures id is non-nil" }
    return !!@insights_accessible_by_user_id[user_id] if @insights_accessible_by_user_id.key?(user_id)
    @insights_accessible_by_user_id[user_id] = user.can_admin_sponsors_listings? || billing_manageable_by?(user)
  end

  # Public: Get the ID of the organization that pays for this organization's sponsorships, if any.
  sig { returns T.nilable(Integer) }
  def sponsoring_linked_organization_id
    organization_profile&.sponsoring_linked_organization_id
  end

  # Public: Sponsorships created by orgs (as sponsors) are not eligible to be matched by GitHub
  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).returns T::Boolean }
  def eligible_for_sponsorship_match?(sponsorable:)
    false
  end

  # Public: Get an email address for sending SponsorshipNewsletter messages to the organization, if they have opted
  # into it.
  sig { returns T.nilable(String) }
  def sponsors_update_email
    organization_profile&.sponsors_update_email
  end

  # Public: Get the id of the Stripe customer associated with this org.
  sig { returns T.nilable(String) }
  def stripe_customer_id
    organization_profile&.stripe_customer_id
  end

  # Public: Does the organization have any open Stripe invoices?
  sig { returns T::Boolean }
  def any_open_stripe_invoices?
    return false unless stripe_customer_id

    invoice_loader = Sponsors::StripeInvoicesLoader.new(
      customer_id: T.must(stripe_customer_id),
      status: Sponsors::StripeInvoicesLoader::InvoiceStatus::Open,
      limit: 1
    )

    loader_result = invoice_loader.fetch
    open_invoices = loader_result.invoices

    open_invoices.any?
  end

  # Public: Get the ID for this organization's Sponsors-specific plan subscription, if they have one.
  #
  # Returns an Integer Billing::PlanSubscription ID or nil
  sig { returns T.nilable(Integer) }
  def sponsors_plan_subscription_id
    sponsors_plan_subscription&.id
  end

  # Public: Create an audit log event for ad-hoc payment runs for Sponsors-specific Zuora accounts
  #
  # actor - User (staff member) starting the payment run
  sig { params(actor: User).void }
  def instrument_sponsors_payment_run(actor:)
    context = {
      prefix: :sponsors,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(actor))
    instrument(:payment_run, context)
  end

  # Public: Create an audit log event for ad-hoc credit balance increase for Sponsors-specific Zuora accounts
  #
  # actor - User (staff member) increasing the credit balance; can pass nil if there is no actor due to the credit
  #         balance increase being done via automation
  # result - the GitHub::Billing::Result of the credit balance increase
  # amount_in_cents - the amount in cents to increase the credit balance
  # comment - the comment attached to the Zuora payment
  # reference_id - the reference id attached to the Zuora payment
  # payment_id - the Zuora payment id (if successful)
  sig do
    params(
      actor: T.nilable(User),
      result: GitHub::Billing::Result,
      amount_in_cents: Integer,
      comment: String,
      reference_id: String,
      payment_id: T.nilable(String),
    ).void
  end
  def instrument_sponsors_credit_balance_increase(actor:, result:, amount_in_cents:, comment:, reference_id:, payment_id:)
    payload = {
      prefix: :sponsors,
      result: result.to_s,
      amount_in_cents: amount_in_cents,
      comment: comment,
      reference_id: reference_id,
      payment_id: payment_id,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(actor))

    instrument(:credit_balance_increase, payload)
  end

  sig { returns T::Boolean }
  def active_sponsors_invoice_migration?
    value = Sponsors::KV.store.get(sponsors_invoice_migration_lock_key).value { nil }
    value.present?
  end

  # Public: Sets the KV value to say that this org's invoiced Sponsors account creation is in progress.
  sig { void }
  def set_active_sponsors_invoice_migration_lock
    data = {
      sponsor_id: id,
      status: "pending",
      started_at: Time.now,
    }.to_json

    Sponsors::KV.store.set(sponsors_invoice_migration_lock_key, data, expires: SPONSORS_INVOICE_MIGRATION_TTL.from_now)
  end

  # Public: Clears the KV value that says that this org's invoiced Sponsors account is being created.
  sig { void }
  def clear_active_sponsors_invoice_migration_lock
    Sponsors::KV.store.del(sponsors_invoice_migration_lock_key)
  end

  # Public: Indicates if this organization has a non-expired signature for an invoiced Sponsors agreement.
  sig { returns T::Boolean }
  def active_invoiced_sponsors_agreement?
    # TODO: https://github.com/github/sponsors/issues/6037
    #       Remove this method and clean up all of its callers

    # We now determine that any org signed up for sponsors invoicing agrees to the terms and conditions
    sponsors_invoiced?
  end

  # Public: Indicates if we show the option to pay the prorated amount when an
  #         org goes create a sponsorship as the default option.
  sig { returns(T::Boolean) }
  def sponsors_prorated_by_default?
    !sponsors_invoiced?
  end

  # Public: Indicates if this organization needs to sign up for invoiced
  #         sponsorships if they want to sponsor someone.
  sig { returns(T::Boolean) }
  def sponsors_invoicing_required_to_sponsor?
    invoiced? && !sponsors_invoiced?
  end

  private

  # Private: Returns the KV key for when we mark that this org is having its
  #          invoiced Sponsors account created.
  sig { returns String }
  def sponsors_invoice_migration_lock_key
    "sponsors.invoice_migration_lock.#{id}"
  end
end
