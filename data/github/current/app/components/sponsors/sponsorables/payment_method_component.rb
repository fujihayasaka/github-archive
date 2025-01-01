# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class PaymentMethodComponent < ApplicationComponent
      # sponsor - the User or Organization who is paying for the sponsorship
      # payment_method - the PaymentMethod the sponsor is using
      def initialize(sponsor:, payment_method:, show_top_border: true)
        @sponsor = sponsor
        @payment_method = payment_method
        @show_top_border = show_top_border
      end

      private

      attr_reader :sponsor, :payment_method, :show_top_border

      def render?
        return false unless GitHub.sponsors_enabled? && GitHub.billing_enabled?
        return false unless sponsor
        return false unless logged_in?
        return false if sponsor.sponsors_invoiced?
        return false if sponsor.organization? && sponsor.business.present?
        return false if sponsor.has_commercial_interaction_restriction?

        sponsor.has_saved_billing_information? || payment_method&.valid_payment_token?
      end

      def show_top_border?
        show_top_border
      end

      def credit_card_last_four
        return unless payment_method.last_four.present?
        "ending #{payment_method.last_four}"
      end

      def credit_card_expiration
        exp_date = payment_method.expiration_date
        return "" unless exp_date
        exp_date.strftime("%-m/%Y")
      end
    end
  end
end
