# typed: true
# frozen_string_literal: true

module Marketplace
  module Listings
    class DelistProceedButtonComponent < ApplicationComponent
      VERIFY_LISTING_NAME = "To confirm, type \"%{listing_conf}\" in the box below"
      STAGES_BUTTON_TEXT = {
        "1" => "I want to delist this app",
        "2" => "I have read and understand these effects",
        "3" => "Delist my listing"
      }.freeze

      def initialize(listing:, stage:)
        @listing = listing
        @stage = stage
      end

      private

      attr_reader :listing, :stage

      def button_text
        STAGES_BUTTON_TEXT[stage.to_s]
      end

      memoize def listing_conf
        "#{listing.owner.display_login}/#{listing.name}"
      end

      def button_type
        if last_stage?
          :submit
        else
          :button
        end
      end

      def last_stage?
        stage == 3
      end

      def next_stage
        stage + 1 unless last_stage?
      end

      def show_verification_input?
        last_stage?
      end

      def verification_label
        VERIFY_LISTING_NAME % { listing_conf: }
      end
    end
  end
end
