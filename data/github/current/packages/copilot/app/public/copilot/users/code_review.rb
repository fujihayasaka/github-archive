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
        if user_object.feature_flag_enabled?(:copilot_code_review_check_ide_access, default: false)
          ::PullRequests::Copilot::CodeReviewAccess.new(actor: user_object, current_repository: nil).can_access_code_review_in_ide?
        else
          true
        end
      end

      sig { returns(T.nilable(T.any(::Copilot::User, ::Copilot::Business))) }
      memoize def billable_entity
        owner = Customer.find_by(id: copilot_user_object.billable_customer_id)&.billable_owner
        return nil unless owner

        if owner.is_a?(::Business)
          ::Copilot::Business.new(owner)
        elsif owner.is_a?(::User)
          ::Copilot::User.new(owner)
        end
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
    end
  end
end
