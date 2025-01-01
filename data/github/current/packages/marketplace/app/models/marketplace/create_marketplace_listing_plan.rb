# typed: true
# frozen_string_literal: true

module Marketplace

  # Public: A Plain Old Ruby Object (PORO) used for creating a Marketplace::ListingPlan
  class CreateMarketplaceListingPlan
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to create a subscription item
    # inputs[:name] - The name of the payment plan.
    # inputs[:slug] - The slug (short name used in a listing's URL) used to look up the listing.
    # inputs[:description] - A short description of the plan.
    # inputs[:price_model] - The pricing model for the plan.
    # inputs[:monthly_price_in_cents] - How much this plan should cost per month in cents.
    # inputs[:yearly_price_in_cents] - How much this plan should cost annually in cents.
    # inputs[:for_account_type] - The types of accounts that can subscribe to the plan.
    # inputs[:unit_name] (optional) - The name of the unit if this plan is per-unit.
    # inputs[:has_free_trial] (optional, default false) - Does this listing plan have a free trial?
    # inputs[:bullet_values] (optional) - An array of bullet contents for this plan.
    # inputs[:viewer] - Current viewer from GraphQL context.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(name:, slug:, description:, price_model:, monthly_price_in_cents:,
                   yearly_price_in_cents:, for_account_type:, unit_name: nil,
                   has_free_trial: false, bullet_values: nil, viewer:)
      @name = name
      @slug = slug
      @description = description
      @price_model = price_model
      @monthly_price_in_cents = monthly_price_in_cents
      @yearly_price_in_cents = yearly_price_in_cents
      @for_account_type = for_account_type
      @unit_name = unit_name
      @has_free_trial = has_free_trial
      @bullet_values = bullet_values
      @viewer = viewer
    end

    def call
      listing = Marketplace::Listing.find_by(slug: slug)
      plan = Marketplace::ListingPlan.new(listing: listing)

      unless plan.allowed_to_edit?(viewer)
        raise ForbiddenError.new("#{viewer.name_with_display_owner} does not have permission to create a plan for the listing.")
      end

      plan.name = name
      plan.description = description
      plan.has_free_trial = has_free_trial
      plan.monthly_price_in_cents = monthly_price_in_cents
      plan.yearly_price_in_cents = yearly_price_in_cents
      plan.unit_name = unit_name
      plan.direct_billing = price_model == Marketplace::ListingPlan::DIRECT_BILLING_PRICE_MODEL
      plan.per_unit = price_model == Marketplace::ListingPlan::PER_UNIT_PRICE_MODEL

      plan.subscription_rules =
        case for_account_type
        when Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["USERS_AND_ORGANIZATIONS"]&.value
          nil
        when Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["USERS_ONLY"]&.value
          :for_users_only
        when Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["ORGANIZATIONS_ONLY"]&.value
          :for_organizations_only
        end

      if bullet_values.present?
        bullet_values.each do |value|
          plan.bullets.build(listing_plan: plan, value: value)
        end
      end

      if plan.save
        plan.instrument_create(actor: viewer)
        { marketplace_listing_plan: plan }
      else
        errors = plan.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not create a Marketplace listing plan: #{errors}")
      end
    end

    private

    attr_reader :name, :slug, :description, :price_model, :monthly_price_in_cents, :yearly_price_in_cents,
                :for_account_type, :unit_name, :has_free_trial, :bullet_values, :viewer
  end
end
