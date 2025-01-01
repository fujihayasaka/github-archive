# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ResequenceMarketplaceListingScreenshot < Platform::Mutations::Base
      description "Updates the sequence of existing Marketplace listing screenshot relative to other screenshots."
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The Marketplace listing screenshot ID to update.", required: true, loads: Objects::MarketplaceListingScreenshot, as: :screenshot
      argument :previous_screenshot_id, ID, "The ID of the screenshot that this screenshot should follow in sequence.", required: true

      field :marketplace_listing_screenshot, Objects::MarketplaceListingScreenshot, "The updated Marketplace listing screenshot.", null: true

      def resolve(screenshot:, **inputs)

        unless screenshot.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change the " +
                                         "Marketplace listing screenshot.")
        end

        previous_screenshot = if inputs[:previous_screenshot_id].present?
          Helpers::NodeIdentification.typed_object_from_id([Objects::MarketplaceListingScreenshot],
                                                           inputs[:previous_screenshot_id], context)
        end

        if screenshot.resequence(after_screenshot: previous_screenshot)
          { marketplace_listing_screenshot: screenshot }
        else
          errors = screenshot.errors.full_messages.join(", ")
          raise Errors::Unprocessable.new("Could not resequence Marketplace listing screenshot: #{errors}")
        end
      end
    end
  end
end
