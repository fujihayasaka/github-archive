# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class InviteAdmin < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Invite owners"
      end

      sig { override.returns(String) }
      def task_link
        enterprise_admins_path(business, show_onboarding_guide_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        business.invitations.with_business_role(Business::OWNER_ROLE).present?
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/permissions.svg"
      end
    end
  end
end
