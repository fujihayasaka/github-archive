# typed: true
# frozen_string_literal: true

module Marketplace

  # Public: A Plain Old Ruby Object (PORO) used for updating an existing Marketplace::ListingPlan
  class UpdateMarketplaceListingPlan
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to create a subscription item
    # inputs[:plan] - The Marketplace::ListingPlan (payment plan) to update.
    # inputs[:name] - The name of the payment plan.
    # inputs[:description] - A short description of the plan.
    # inputs[:price_model] - The pricing model for the plan.
    # inputs[:monthly_price_in_cents] - How much this plan should cost per month in cents.
    # inputs[:yearly_price_in_cents] - How much this plan should cost annually in cents.
    # inputs[:unit_name] (optional) - The name of the unit if this plan is per-unit.
    # inputs[:has_free_trial] (optional) - Does this listing plan have a free trial?
    # inputs[:for_account_type] - The types of accounts that can subscribe to the plan.
    # inputs[:viewer] - Current viewer from GraphQL context.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(plan:, name:, description:, price_model:, monthly_price_in_cents:, yearly_price_in_cents:,
                   unit_name: nil, has_free_trial: false, for_account_type:, viewer:)
      @plan = plan
      @name = name
      @description = description
      @price_model = price_model
      @monthly_price_in_cents = monthly_price_in_cents
      @yearly_price_in_cents = yearly_price_in_cents
      @unit_name = unit_name
      @has_free_trial = has_free_trial
      @for_account_type = for_account_type
      @viewer = viewer
    end

    def call
      unless plan.allowed_to_edit?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to change the " \
                                 "Marketplace listing plan.")
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
        when T.must(Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["USERS_AND_ORGANIZATIONS"]).value
          nil
        when T.must(Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["USERS_ONLY"]).value
          :for_users_only
        when T.must(Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.values["ORGANIZATIONS_ONLY"]).value
          :for_organizations_only
        end

      if plan.save
        plan.listing.set_filter_categories!
        plan.instrument_update(actor: viewer)
        { marketplace_listing_plan: plan }
      else
        errors = plan.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not update Marketplace listing plan: #{errors}")
      end
    end

    private

    attr_reader :plan, :name, :description, :price_model, :monthly_price_in_cents, \
                :yearly_price_in_cents, :unit_name, :has_free_trial, :for_account_type, :viewer
  end
end
