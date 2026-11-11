# typed: true
# frozen_string_literal: true

module Marketplace
  module Listings
    class DelistComponent < ApplicationComponent
      attr_reader :listing

      def initialize(listing:)
        @listing = listing
      end
    end
  end
end
