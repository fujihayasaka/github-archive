# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class InviteEnterpriseMember < Base
      sig { override.returns(String) }
      def title
        "Invite enterprise members"
      end

      sig { override.returns(String) }
      def task_link
        people_enterprise_path(business, show_onboarding_guide_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        business.invitations.with_business_role(Business::UNAFFILIATED_ROLE).present? || business.user_accounts.exclusive_unaffiliated_role.present?
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/permissions.svg"
      end
    end
  end
end
