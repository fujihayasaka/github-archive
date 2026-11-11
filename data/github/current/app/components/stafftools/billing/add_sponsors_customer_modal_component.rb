# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class AddSponsorsCustomerModalComponent < ApplicationComponent
      sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      sig { returns T::Boolean }
      memoize def render?
        !!(GitHub.sponsors_enabled? && sponsor.sponsors_customer.nil?)
      end

      private

      sig { returns GitHubSponsors::Types::Sponsor }
      attr_reader :sponsor
    end
  end
end
