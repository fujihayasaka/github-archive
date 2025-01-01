# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsTrustLevelFormComponent < ApplicationComponent
      # target - User/Org to update
      # target_type - type of trust to update (:sponsor, :sponsorable)
      # trust_level - trust level to set (:calculated, :untrusted, :neutral, :trusted)
      def initialize(target:, target_type:, trust_level:)
        @target = target
        @target_type = fetch_or_fallback(target_types, target_type, :sponsor)
        @trust_level = fetch_or_fallback(trust_levels, trust_level, :calculated)
      end

      private

      def render?
        GitHub.sponsors_enabled? && current_user&.site_admin?
      end

      def trust_levels
        ::Sponsors::TrustLevel::TRUST_LEVEL_OPTIONS
      end

      def target_types
        ::Sponsors::TrustLevel::TARGET_TYPES
      end
    end
  end
end
