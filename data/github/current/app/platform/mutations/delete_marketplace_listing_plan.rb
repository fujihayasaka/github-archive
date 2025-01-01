# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMarketplaceListingPlan < Platform::Mutations::Base
      description "Deletes a Marketplace listing payment plan."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing plan ID to delete.", required: true, loads: Objects::MarketplaceListingPlan, as: :plan

      field :marketplace_listing, Objects::MarketplaceListing, "The Marketplace listing from which the plan was deleted.", null: true

      def resolve(plan:, **inputs)
        unless plan.allowed_to_delete?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete the listing plan.")
        end

        if plan.destroy
          { marketplace_listing: plan.listing }
        else
          errors = plan.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not delete listing plan: #{errors}")
        end
      end
    end
  end
end
