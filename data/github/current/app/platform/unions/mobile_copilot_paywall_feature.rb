# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class MobileCopilotPaywallFeature < Platform::Unions::Base
      description "A feature in the paywall that can be either a plan feature comparison or chat models information"
      required_capabilities [:mobile_only_schema_mask]

      possible_types Objects::MobileCopilotFeatureComparisonSubsection, Objects::MobileCopilotPaywallChatModels

      def self.resolve_type(object, _context)
        case object
        when Mobile::Copilot::Paywall::FeatureComparisonSubsection
          Objects::MobileCopilotFeatureComparisonSubsection
        when Mobile::Copilot::Paywall::ChatModels
          Objects::MobileCopilotPaywallChatModels
        else
          raise Errors::Internal, "Unexpected MobileCopilotPaywallFeature type: #{object.class}"
        end
      end
    end
  end
end
