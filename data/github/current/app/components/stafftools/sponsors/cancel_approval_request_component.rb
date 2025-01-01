# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class CancelApprovalRequestComponent < ApplicationComponent
      def initialize(listing:)
        @listing = listing
      end

      private

      def render?
        return false unless @listing
        @listing.can_cancel_approval_request?
      end
    end
  end
end
