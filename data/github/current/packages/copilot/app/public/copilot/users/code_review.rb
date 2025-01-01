# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module CodeReview
      extend T::Helpers

      include Copilot::Users::Signatures

      abstract!

      # This method is used to check if the user can access the repo control/content exclusion functionality
      sig { override.returns(T::Boolean) }
      def copilot_code_review_enabled?
        user_object.feature_flag_enabled_or_raise?(:copilot_code_review_v1) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        user_object.feature_flag_enabled_or_raise?(:copilot_code_review_public_preview) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        user_object.feature_flag_enabled_or_raise?(:copilot_code_review_ga) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end
    end
  end
end
