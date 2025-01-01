# typed: true
# frozen_string_literal: true

module SponsorsTier::ZuoraDependency
  extend T::Helpers

  ZUORA_PRODUCT_TYPE = "sponsorable.sponsors_tier"

  requires_ancestor { SponsorsTier }

  # Public: Determine if a sponsorship using this tier should be locked to allow Zuora time to
  # process billing.
  #
  # active - whether the sponsorship is still active (i.e. not cancelled or expired).
  # selected_at - the time when this tier was chosen for the sponsorship
  sig do
    params(
      active: T.nilable(T::Boolean),
      selected_at: T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone))
    ).returns(T.nilable(T::Boolean))
  end
  def locked_sponsorship?(active:, selected_at:)
    # we need to lock one-time sponsorships to allow Zuora enough time to process
    # billing. Invoiced sponsorships are a type of one-time sponsorships but they
    # don't interact with Zuora so there's no need to lock them.
    return false if invoiced?

    # Sponsorships that have been deactivated due to billing issues or cancellation
    # should be considered unlocked so the user can update billing information
    # and try again.
    return false unless active

    # Recurring sponsorships are never locked
    one_time? &&

      # If the one-time tier was chosen within the last 2 days, assume
      # we haven't finished processing on Zuora and that we should be locked
      selected_at &&
      selected_at > Sponsorship::LOCK_CUTOFF_IN_DAYS.days.ago
  end

  sig { params(billing_cycle: T.any(String, Symbol)).returns(T.nilable(::Billing::ProductUUID)) }
  def product_uuid(billing_cycle)
    ::Billing::ProductUUID.find_by(product_type: ZUORA_PRODUCT_TYPE, product_key: id,
      billing_cycle: billing_cycle.to_s)
  end

  # Public: Returns the ProductRatePlanId for this tier and the given cycle in Zuora
  #
  # cycle: "year" or "month" - the billing cycle we want the zuora id for
  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def zuora_id(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_id
  end

  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def zuora_charge_ids(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_charge_ids
  end

  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def zuora_product_id(cycle:)
    product_uuid(cycle)&.zuora_product_id
  end

  # Public: The Zuora product rate plan ID for this tier's listing
  #
  # Zuora synchronization isn't 100% reliable, and there may be cases
  # where a listing UUID doesn't exist. When all subscriptions have been
  # migrated to use listing-based rate plans, this will no longer be a
  # problem since the rate plan can't be on an active subscription if the
  # sync wasn't successful as we won't have a UUID for it yet. While we
  # still have a mix of tier-based and listing-based subscriptions, this
  # lookup guards against a missing product UUID for the listing.
  #
  # cycle: find the product rate plan ID for this billing cycle
  #
  # Returns a String product rate plan ID
  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def listing_product_rate_plan_id(cycle:)
    listing.product_uuid(cycle)&.zuora_product_rate_plan_id
  end

  # Public: Returns true if this tier matches an invoice_item:
  # 1. For a tier-based Zuora product subscription, this returns true if
  #    this tier's listing name is part of the invoice_item's charge_name
  #    E.g. tier-based charge_name: "sponsors-banana: $5 a month - month"
  # 2. For a listing-based Zuora product subscription, this returns true if
  #    this listing's monthly or yearly charge_name exactly matches
  #    the invoice_item's charge_name
  #    E.g. listing-based charge_name: "sponsors-user-1234: Recurring monthly"
  #
  # This needs to support both tier-based and listing-based Zuora
  # product subscriptions until our migration is complete.
  # See https://github.com/github/sponsors/issues/1843.
  #
  # invoice_item        - A Billing::Zuora::InvoiceItem
  # match_copilot_cycle - Unused here. Only here for consistency with ProductUUID#match_invoice_item?
  sig { params(invoice_item: Billing::Zuora::InvoiceItem, match_copilot_cycle: T::Boolean).returns(T::Boolean) }
  def matches_invoice_item?(invoice_item, match_copilot_cycle: false)
    # Make sure the listing exists
    return false unless listing.present?

    # Check for tier-based Zuora product subscription
    charge_name_prefix = invoice_item.charge_name.split(":").first.to_s
    return true if charge_name_prefix.downcase == listing.name.downcase

    # Check for listing-based Zuora product subscription
    invoice_item.charge_name == listing.monthly_plan_or_charge_name ||
      invoice_item.charge_name == listing.yearly_plan_or_charge_name
  end
end
