# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class EnterprisePaymentMethodComponent < ApplicationComponent
      extend T::Sig

      # sponsor - User or Organization creating the sponsorship
      sig { params(sponsor: T.any(User, Organization)).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      private

      attr_reader :sponsor
      delegate :business, to: :sponsor, allow_nil: true

      sig { returns(T::Boolean) }
      def render?
        return false unless sponsor.organization?

        !sponsor.sponsors_invoiced? && business.present? && business.self_serve_payment?
      end
    end
  end
end
