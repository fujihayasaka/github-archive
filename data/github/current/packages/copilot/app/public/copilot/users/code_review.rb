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
        user_object.feature_enabled?(:copilot_code_review_v1) ||
        user_object.feature_enabled?(:copilot_code_review_public_preview) ||
        user_object.feature_enabled?(:copilot_code_review_ga)
      end
    end
  end
end
