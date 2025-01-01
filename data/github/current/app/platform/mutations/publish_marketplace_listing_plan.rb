# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PublishMarketplaceListingPlan < Platform::Mutations::Base
      description "Publish a Marketplace listing plan."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing plan ID to publish.", required: true, loads: Objects::MarketplaceListingPlan, as: :plan

      field :marketplace_listing_plan, Objects::MarketplaceListingPlan, "The published Marketplace listing plan.", null: true

      def resolve(plan:, **inputs)
        unless plan.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change the " +
                                         "Marketplace listing plan.")
        end

        if plan.draft? && plan.can_publish?
          plan.publish!
        else
          raise Errors::Unprocessable.new(plan.unpublishable_reason)
        end

        { marketplace_listing_plan: plan }
      end
    end
  end
end
