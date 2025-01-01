# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class InviteAdmin < Base
      sig { override.returns(String) }
      def title
        "Invite owners"
      end

      sig { override.returns(String) }
      def task_link
        if business.enterprise_managed?
          "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-for-enterprise-managed-users"
        else
          enterprise_admins_path(business, show_onboarding_guide_tip: true)
        end
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        if business.enterprise_managed?
          business.admins.count > 1
        else
          business.invitations.with_business_role(Business::OWNER_ROLE).present?
        end
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/permissions.svg"
      end
    end
  end
end
