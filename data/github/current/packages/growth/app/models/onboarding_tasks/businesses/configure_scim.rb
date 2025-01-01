# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class ConfigureSCIM < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Configure provisioning"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        nil
      end

      sig { returns(T.nilable(String)) }
      def task_link_text
        nil
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        business.user_accounts.count > 1
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end

      sig { returns(String) }
      def help_link
        "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-with-scim/configuring-scim-provisioning-for-users#configuring-provisioning-for-enterprise-managed-users"
      end

      sig { returns(String) }
      def help_link_text
        "Read our guide for configuring provisioning"
      end
    end
  end
end
