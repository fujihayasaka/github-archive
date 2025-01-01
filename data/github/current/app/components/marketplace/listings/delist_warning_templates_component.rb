# typed: true
# frozen_string_literal: true

module Marketplace
  module Listings
    class DelistWarningTemplatesComponent < ApplicationComponent
      def initialize(listing:)
        @listing = listing
      end

      private

      attr_reader :listing
    end
  end
end
