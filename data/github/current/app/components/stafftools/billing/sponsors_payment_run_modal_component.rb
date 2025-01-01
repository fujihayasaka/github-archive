# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsPaymentRunModalComponent < ApplicationComponent
      extend T::Sig
      include Stafftools::BillingHelper

      # sponsor - a User or Organization
      # sponsors_customer - a Customer with purpose=sponsors that belongs to the given `sponsor`
      sig { params(sponsor: T.nilable(::User)).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      sig { returns(T::Boolean) }
      memoize def render?
        !!(GitHub.sponsors_enabled? && sponsor&.sponsors_invoiced?)
      end

      private

      sig { returns(T.nilable(::User)) }
      attr_reader :sponsor
      delegate :sponsors_customer, to: :sponsor, private: true
    end
  end
end
