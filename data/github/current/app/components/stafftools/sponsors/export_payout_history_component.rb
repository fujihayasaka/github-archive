# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class ExportPayoutHistoryComponent < ApplicationComponent
      def initialize(sponsors_listing:)
        @sponsors_listing = sponsors_listing
      end

      private

      attr_reader :sponsors_listing

      delegate :sponsorable_login, to: :sponsors_listing

      def render?
        GitHub.sponsors_enabled? && sponsors_listing&.fiscal_host? && logged_in?
      end
    end
  end
end
