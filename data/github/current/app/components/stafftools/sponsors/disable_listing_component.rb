# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class DisableListingComponent < ApplicationComponent
      def initialize(listing:)
        @listing = listing
      end

      private

      def render?
        return false unless @listing
        @listing.can_disable?
      end
    end
  end
end
