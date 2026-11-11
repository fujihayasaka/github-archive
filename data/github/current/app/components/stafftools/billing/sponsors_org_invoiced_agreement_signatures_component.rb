# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsOrgInvoicedAgreementSignaturesComponent < ApplicationComponent

      # sponsor - a User or Organization
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      private

      attr_reader :sponsor

      def render?
        GitHub.sponsors_enabled? && sponsor.present? && logged_in?
      end

      memoize def signatures
        SponsorsInvoicedAgreementSignature.for_org(sponsor).includes(:agreement, :signatory).to_a
      end
    end
  end
end
