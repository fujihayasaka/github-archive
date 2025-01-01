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
        return false if user_object.feature_enabled?(:copilot_code_review_public_preview_denylist)

        user_object.feature_enabled?(:copilot_pr_reviews_v1) || user_object.feature_enabled?(:copilot_code_review_public_preview)
      end
    end
  end
end
