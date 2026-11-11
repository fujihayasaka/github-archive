# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module CodeReview
      extend T::Helpers

      include Copilot::Users::Signatures
      include GitHub::Memoizer

      abstract!

      # This method is used to check if the user can access the repo control/content exclusion functionality
      sig { override.returns(T::Boolean) }
      def copilot_code_review_enabled?
        unless user_object.feature_flag_enabled?(:copilot_code_review_check_ide_access, default: false)
          return true
        end

        result = ::PullRequests::Copilot::CodeReviewAccess.new(actor: user_object, current_repository: nil).can_access_code_review_in_ide?
        if !result && user_object.feature_flag_enabled?(:copilot_token_service_ccr_debug, default: false)
          log_code_review_disabled_reason
        end
        result
      end

      sig { override.returns(T::Boolean) }
      def ccr_globally_blocked?
        # Check EMU-specific blocking first.
        if user_object.is_enterprise_managed?
          emu_business = user_object.enterprise_managed_business
          return !emu_business&.code_review_repository_access_enabled?
        end
        # Important note! This feature flag will block users who are part of _any_ enterprise with CCR blocked from
        # accessing CCR in the IDE, even if the code being reviewed does not belong to the blocking enterprise.
        copilot_businesses.any? do |business|
          business.business_object.feature_flag_enabled?(:ccr_enable_global_block, default: false) &&
            !business.business_object.code_review_repository_access_enabled?
        end
      end

      private

      sig { void }
      def log_code_review_disabled_reason
        user = user_object
        public_user = ::Copilot::Public::User.new(user)

        reason = if public_user.copilot_businesses.any? { |business| !business.business_object.code_review_repository_access_enabled? }
          "business_ccr_repository_access_disabled"
        elsif !public_user.has_copilot_access?
          "no_copilot_access"
        elsif public_user.has_limited_access?
          "limited_copilot_access"
        elsif !public_user.code_review_enabled?
          "code_review_policy_disabled"
        else
          "unknown"
        end

        GitHub.logger.info(
          "copilot_code_review_enabled returned false",
          "gh.copilot.code_review.disabled_reason" => reason,
          "gh.user.analytics_tracking_id" => user.analytics_tracking_id,
        )
      end
    end
  end
end
