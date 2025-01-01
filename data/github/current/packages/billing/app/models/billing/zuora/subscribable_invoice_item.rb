# typed: strict
# frozen_string_literal: true

# Public: a subclass of InvoiceItem that references a subscribable such as a
# SponsorsTier or Marketplace::ListingPlan. Used when processing invoice items
# that have rate plans with subscribable tracking IDs.
class Billing::Zuora::SubscribableInvoiceItem < Billing::Zuora::InvoiceItem
  sig { returns(T.nilable(Billing::SubscriptionItem)) }
  attr_reader :subscription_item

  sig { params(charge_amount: Billing::Money).returns(Billing::Money) }
  attr_writer :charge_amount

  sig do
    params(
      raw_zuora_response: T::Hash[String, T.untyped],
      subscribable: T.nilable(T.any(SponsorsTier, Marketplace::ListingPlan, Billing::ProductUUID)),
      subscription_item: T.nilable(Billing::SubscriptionItem)
    ).void
  end
  def initialize(raw_zuora_response, subscribable: nil, subscription_item: nil)
    super(raw_zuora_response)
    @subscribable = subscribable
    @subscription_item = subscription_item
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless super(other)
    other_subscribable = other.subscribable
    other_subscription_item = other.subscription_item
    subscribable == other_subscribable && subscription_item == other_subscription_item
  end

  # Whether this invoice item references a subscribable such as a sponsors tier. so
  # consumers of can determine whether they'll need to do their own subscribable lookup.
  #
  # This will generally be false for the base class, and true for subclasses like this.
  sig { returns(T::Boolean) }
  def subscribable?
    true
  end

  # Public: Get the subscribable related to this invoice item.
  #
  # Prefers the subscribable from the subscription item, but will fall back to an explicitly specified subscribable
  # for backwards compatibility.
  sig { returns(T.any(SponsorsTier, Marketplace::ListingPlan, Billing::ProductUUID)) }
  def subscribable
    subscription_item = self.subscription_item
    if subscription_item.present?
      subscription_item.subscribable
    else
      @subscribable
    end
  end

  # Public: Get the entity (User/Org/Business) that manages the related subscription item.
  #
  # This support Marketplace and Sponsors items where an enterprise account may pay for an item,
  # but a member organization manages it.
  sig { returns(T.nilable(Billing::Types::Account)) }
  def managing_entity
    return unless subscription_item = self.subscription_item
    subscription_item.organization || subscription_item.account
  end

  # Public: Get a Hash of info that will be included with billing transaction line items for this invoice item.
  sig { returns(T.nilable(T::Hash[String, String])) }
  def line_item_extras
    managing_entity_id = if managing_entity && managing_entity != T.must(subscription_item).account
      managing_entity&.id
    end

    if managing_entity_id
      {
        Billing::BillingTransaction::LineItem::MANAGING_ENTITY_ID_KEY => managing_entity_id,
      }
    else
      nil
    end
  end

  # Public: Does this invoice item represent a sponsorship charge?
  sig { returns(T::Boolean) }
  def sponsors_item?
    subscribable.is_a?(SponsorsTier)
  end

  # Public: Whether this invoice item represents a service fee charged by GitHub for a sponsorship.
  sig { returns(T::Boolean) }
  def sponsors_fee_charge?
    sponsors_item? &&
      # Keep in sync with how SponsorsListing::ZuoraDependency#create_rate_plans constructs charge names:
      charge_name.ends_with?(SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX)
  end

  # Public: Whether this invoice item represents a zero dollar service fee charged by GitHub for a sponsorship.
  sig { returns(T::Boolean) }
  def zero_dollar_sponsors_fee_charge?
    sponsors_item? &&
      # Keep in sync with how SponsorsListing::ZuoraDependency#create_rate_plans constructs charge names:
      charge_name.ends_with?(SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX) &&
      charge_amount.zero?
  end
end
