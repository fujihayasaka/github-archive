# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RetireMarketplaceListingPlan < Platform::Mutations::Base
      description "Retire a Marketplace listing plan."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing plan ID to retire.", required: true, loads: Objects::MarketplaceListingPlan, as: :plan

      field :marketplace_listing_plan, Objects::MarketplaceListingPlan, "The retired Marketplace listing plan.", null: true

      def resolve(plan:, **inputs)
        if plan.retired?
          raise Errors::Unprocessable.new("Can't change the state of retired listing plans.")
        elsif !plan.allowed_to_edit?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change the listing plan.")
        end

        begin
          plan.retire!(actor: context[:viewer])
        rescue Marketplace::ListingPlan::RetirementNotAllowed => e
          raise Errors::Unprocessable.new(e.message)
        end

        { marketplace_listing_plan: plan }
      end
    end
  end
end
