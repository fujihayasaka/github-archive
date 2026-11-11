# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class CreatePayoutRestrictionComponent < ApplicationComponent
      def initialize(sponsorable:)
        @sponsorable = sponsorable
      end

      private

      attr_reader :sponsorable

      def payout_restricted?
        sponsorable.has_commercial_interaction_restriction?
      end

      def render?
        payout_restricted?
      end
    end
  end
end
