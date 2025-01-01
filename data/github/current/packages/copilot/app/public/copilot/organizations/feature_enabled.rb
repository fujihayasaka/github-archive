# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module FeatureEnabled
      extend T::Helpers
      include Copilot::Organizations::Signatures

      abstract!

      sig { params(feature_name: Symbol).returns(T::Boolean) }
      def feature_flag_enabled_or_raise?(feature_name)
        return true if organization_object.feature_flag_enabled_or_raise?(feature_name) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return true if self.copilot_business&.business_object&.feature_flag_enabled_or_raise?(feature_name) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        false
      end
      alias feature_enabled? feature_flag_enabled_or_raise?

      sig { params(feature_name: Symbol, default: T::Boolean).returns(T::Boolean) }
      def feature_flag_enabled?(feature_name, default:)
        return true if organization_object.feature_flag_enabled?(feature_name, default: default)

        return true if self.copilot_business&.business_object&.feature_flag_enabled?(feature_name, default: default)

        false
      end
    end
  end
end
