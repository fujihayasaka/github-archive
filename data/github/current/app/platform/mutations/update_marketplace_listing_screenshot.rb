# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateMarketplaceListingScreenshot < Platform::Mutations::Base
      description "Updates an existing Marketplace listing screenshot."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing screenshot ID to update.", required: true, loads: Objects::MarketplaceListingScreenshot, as: :screenshot
      argument :caption, String, "A caption that describes the screenshot image.", required: true

      field :marketplace_listing_screenshot, Objects::MarketplaceListingScreenshot, "The updated Marketplace listing screenshot.", null: true

      def resolve(screenshot:, **inputs)

        unless screenshot.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change the " +
                                         "Marketplace listing screenshot.")
        end

        screenshot.caption = inputs[:caption]

        if screenshot.save
          { marketplace_listing_screenshot: screenshot }
        else
          errors = screenshot.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not update Marketplace listing screenshot: #{errors}")
        end
      end
    end
  end
end
