# typed: strict
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class TradeScreeningCannotProceedComponent < ApplicationComponent
      include TradeControlsHelper

      # sponsor - the User or Organization who is paying for the sponsorship
      # show_title - Boolean indicating whether the title should be shown; Boolean
      # show_border - Boolean indicating whether the top border should be shown; Boolean
      sig do
        params(
          sponsor: Billing::Types::Account,
          show_title: T::Boolean,
          show_border: T::Boolean,
        )
        .void
      end
      def initialize(sponsor:, show_title: true, show_border: true)
        @sponsor = sponsor
        @show_title = show_title
        @show_border = show_border
      end

      private

      sig { returns(Billing::Types::Account) }
      attr_reader :sponsor

      delegate :has_commercial_interaction_restriction?, :org_is_on_business_tos?, to: :sponsor

      sig { returns(T::Boolean) }
      def render?
        has_commercial_interaction_restriction?
      end

      sig { returns(T::Boolean) }
      def show_title?
        @show_title
      end

      sig { returns(T::Boolean) }
      def show_border?
        @show_border
      end
    end
  end
end
