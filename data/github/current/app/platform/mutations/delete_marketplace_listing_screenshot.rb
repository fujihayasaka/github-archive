# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMarketplaceListingScreenshot < Platform::Mutations::Base
      description "Deletes a Marketplace listing screenshot."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing screenshot ID to delete.", required: true, loads: Objects::MarketplaceListingScreenshot, as: :screenshot

      field :marketplace_listing, Objects::MarketplaceListing, "The Marketplace listing from which the screenshot was deleted.", null: true

      def resolve(screenshot:, **inputs)

        unless screenshot.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to remove " +
                                         "screenshots from this Marketplace listing.")
        end

        if screenshot.destroy
          { marketplace_listing: screenshot.listing }
        else
          errors = screenshot.errors.full_messages.join(", ")
          message = "Could not delete Marketplace listing screenshot: #{errors}"
          raise Errors::Unprocessable.new(message)
        end
      end
    end
  end
end
