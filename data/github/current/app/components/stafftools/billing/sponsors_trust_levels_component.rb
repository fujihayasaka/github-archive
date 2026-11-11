# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsTrustLevelsComponent < ApplicationComponent
      # user - a User or Organization
      def initialize(user:)
        @user = user
      end

      private

      def render?
        GitHub.sponsors_enabled? && @user.present?
      end

      def trust_levels
        ::Sponsors::TrustLevel::TRUST_LEVEL_OPTIONS
      end

      memoize def trust_level_as_sponsor
        @user.trust_level_as_sponsor
      end

      memoize def trust_level_as_sponsorable
        @user.trust_level_as_sponsorable
      end
    end
  end
end
