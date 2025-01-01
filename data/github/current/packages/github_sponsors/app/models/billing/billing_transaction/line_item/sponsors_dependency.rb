# typed: strict
# frozen_string_literal: true

module Billing::BillingTransaction::LineItem::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Billing::BillingTransaction::LineItem }

  delegate :instrument_transfer_failure, to: :sponsorship

  included do
    T.bind(self, T.class_of(Billing::BillingTransaction::LineItem))

    scope :sponsorships, -> { where(subscribable_type: SponsorsTier.name) }

    has_one :sponsorship, ->(line_item) do
      T.bind(self, T.untyped)
      if line_item.subscribable_SponsorsTier? && line_item.subscribable_id
        tier_id = line_item.subscribable_id
        sponsor_id = line_item.sponsor_id
        unscope(where: :line_item_id).joins(:tier)
          .joins(
            "LEFT OUTER JOIN sponsors_tiers AS listing_tiers "\
            "ON listing_tiers.sponsors_listing_id = sponsors_tiers.sponsors_listing_id"
          )
          .from_sponsor(sponsor_id)
          .where(listing_tiers: { id: tier_id })
      else
        none
      end
    end

    has_one :sponsors_listing, ->(line_item) do
      T.bind(self, T.untyped)
      if line_item.subscribable_SponsorsTier? && line_item.subscribable_id
        unscope(where: :line_item_id).for_tier(line_item.subscribable_id)
      else
        none
      end
    end

    scope :sponsorships_excluding_prorated, -> do
      base_query = sponsorships
      tier_ids = base_query.pluck(:subscribable_id)
      tier_prices_by_id = SponsorsTier.where(id: tier_ids)
        .pluck(:id, :monthly_price_in_cents, :yearly_price_in_cents)
        .map { |id, monthly, yearly| [id, [monthly, yearly]] }.to_h
      if tier_prices_by_id.empty?
        none
      else
        tier_id, prices = tier_prices_by_id.first
        line_items = base_query.for_subscribable_id_and_amount_in_cents(tier_id, prices)
        tier_prices_by_id.drop(1).each do |tier_id, prices|
          line_items = line_items.or(base_query.for_subscribable_id_and_amount_in_cents(tier_id, prices))
        end
        line_items
      end
    end

    after_create :deactivate_one_time_sponsors_payment, if: :subscribable_SponsorsTier?

    # Public: Find all line items that funded a particular user or organization via sponsorship.
    #
    # user_or_id - a User, Organization, or their ID
    scope :paying_sponsorable, ->(user_or_id) do
      # Published, retired, custom, and invoiced tiers are available for use with sponsorships:
      subscribable_ids = SponsorsTier.for_sponsorable(user_or_id).without_draft_state.distinct.pluck(:id)
      sponsorships.where(subscribable_id: subscribable_ids)
    end
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
  def sponsor
    return user if user.present?
    User.find_by(id: sponsor_id)
  end

  sig { returns T.nilable(Integer) }
  def sponsor_id
    managing_entity_key = Billing::BillingTransaction::LineItem::MANAGING_ENTITY_ID_KEY
    self.extras&.dig(managing_entity_key) || billing_transaction_user_id
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  def sponsorable
    return unless subscribable_SponsorsTier?
    subscribable&.sponsorable
  end

  sig { returns T.nilable(String) }
  def sponsors_stripe_transfer_account_id
    sponsors_listing&.stripe_transfer_account_id
  end

  # Public: Does this line item represent a fee charge for a sponsorship?
  sig { returns T::Boolean }
  def sponsors_fee?
    return false unless subscribable_SponsorsTier?

    # Keep in sync with SponsorsTier#line_item_description
    description.ends_with?(SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX)
  end

  private

  sig { void }
  def deactivate_one_time_sponsors_payment
    plan_sub = plan_subscription
    return unless plan_sub && subscribable&.one_time?

    subscription_item = Billing::SubscriptionItem.for_sponsors_one_time_payment(T.must(subscribable_id), plan_sub)
    # deactivate without callbacks so we don't trigger a Zuora sync
    subscription_item&.deactivate_without_callbacks
  end
end
