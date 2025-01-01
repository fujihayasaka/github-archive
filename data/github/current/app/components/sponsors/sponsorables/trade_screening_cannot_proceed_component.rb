# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class TradeScreeningCannotProceedComponent < ApplicationComponent
      include TradeControlsHelper

      # sponsor - the User or Organization who is paying for the sponsorship
      # show_title - Boolean indicating whether the title should be shown; Boolean
      def initialize(sponsor:, show_title: true)
        @sponsor = sponsor
        @show_title = show_title
      end

      private

      attr_reader :sponsor
      delegate :org_is_on_business_tos?, :has_lic_r_stopgap_restriction?, to: :sponsor

      def render?
        return false if org_is_on_business_tos? && has_lic_r_stopgap_restriction?

        trade_screening_error_data.present?
      end

      def show_title?
        @show_title
      end

      memoize def trade_screening_error_data
        trade_screening_cannot_proceed_error_data(target: sponsor)
      end
    end
  end
end
