# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateMarketplaceListingPlan < Platform::Mutations::Base
      description "Creates a new Marketplace listing payment plan."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :name, String, "The name of the payment plan.", required: true
      argument :slug, String, "Select the listing that matches this slug. It's the short name of the listing used in its URL.", required: true

      argument :description, String, "A short description of the plan.", required: true
      argument :price_model, Enums::MarketplaceListingPlanPriceModel, "The pricing model for the plan.", required: true
      argument :monthly_price_in_cents, Integer, "How much this plan should cost per month in cents.", required: true
      argument :yearly_price_in_cents, Integer, "How much this plan should cost annually in cents.", required: true
      argument :unit_name, String, "The name of the unit if this plan is per-unit.", required: false
      argument :has_free_trial, Boolean, "Does this listing plan have a free trial?", required: false
      argument :for_account_type, Enums::MarketplaceListingPlanSubscriberAccountTypes, "The types of accounts that can subscribe to the plan.", required: true
      argument :bullet_values, [String], "An array of bullet contents for this plan.", required: false

      field :marketplace_listing_plan, Objects::MarketplaceListingPlan, "The new Marketplace listing plan.", null: true

      def resolve(**inputs)
        Marketplace::CreateMarketplaceListingPlan.call(
          slug: inputs[:slug],
          name: inputs[:name],
          description: inputs[:description],
          price_model: inputs[:price_model],
          monthly_price_in_cents: inputs[:monthly_price_in_cents],
          yearly_price_in_cents: inputs[:yearly_price_in_cents],
          for_account_type: inputs[:for_account_type],
          unit_name: inputs[:unit_name],
          has_free_trial: inputs[:has_free_trial],
          bullet_values: inputs[:bullet_values],
          viewer: context[:viewer],
        )
      rescue Marketplace::CreateMarketplaceListingPlan::ForbiddenError => e
        raise Errors::Forbidden.new(e.message)
      rescue Marketplace::CreateMarketplaceListingPlan::UnprocessableError => e
        raise Errors::Unprocessable.new(e.message)
      end
    end
  end
end
