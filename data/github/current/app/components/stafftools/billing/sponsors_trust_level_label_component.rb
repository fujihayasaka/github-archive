# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorsTrustLevelLabelComponent < ApplicationComponent
      # sponsors_trust_level - a Sponsors::TrustLevel::Result
      def initialize(sponsors_trust_level)
        @sponsors_trust_level = sponsors_trust_level
      end

      def call
        scheme = if @sponsors_trust_level.untrusted?
          :danger
        elsif @sponsors_trust_level.neutral?
          :warning
        else
          :success
        end

        render Primer::Beta::Label.new(
          scheme: scheme,
          test_selector: "#{@sponsors_trust_level.target_type}-trust-level"
        ).with_content(label_content)
      end

      private

      def label_content
        trust_level = @sponsors_trust_level.to_s.titleize
        description = @sponsors_trust_level.forced? ? "Forced" : "Calculated"
        "#{trust_level} (#{description})"
      end

      def render?
        @sponsors_trust_level.present?
      end
    end
  end
end
