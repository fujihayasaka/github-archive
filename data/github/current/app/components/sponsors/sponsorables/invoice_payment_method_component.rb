# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class InvoicePaymentMethodComponent < ApplicationComponent
      include ViewComponent::InlineTemplate

      # sponsor - an invoiced Organization
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      erb_template <<~ERB
        <hr class="my-3">
        <%= render(Primer::Beta::Heading.new(tag: :h4, mb: 3).with_content("Payment method")) %>
        <%= primer_octicon(icon: "credit-card") %>
        <%= render Primer::Beta::Text.new(
          font_weight: :bold,
          ml: 1,
          test_selector: "invoice-balance-payment-method",
        ).with_content("Invoice balance") %>
        <%= render Primer::Beta::Text.new(
          tag: :p,
          classes: "note",
          ml: 4,
        ).with_content("This charge will be deducted from your sponsorship balance.") %>
      ERB

      private

      attr_reader :sponsor

      def render?
        sponsor.present? && sponsor.sponsors_invoiced? && GitHub.sponsors_enabled?
      end
    end
  end
end
