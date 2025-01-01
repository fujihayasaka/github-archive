# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class RequiresAdditionalReviewListingComponent < ApplicationComponent
      def initialize(listing:)
        @listing = listing
      end

      private

      def render?
        return false unless @listing
        @listing.can_require_additional_review?
      end
    end
  end
end
