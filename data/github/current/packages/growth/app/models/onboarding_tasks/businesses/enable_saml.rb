# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class EnableSaml < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Enable single sign-on"
      end

      sig { override.returns(String) }
      def task_link
        settings_security_enterprise_path(business, show_onboarding_guide_tip: true)
      end

      sig { returns(String) }
      def task_link_text
        completed? ? "Manage SSO" : title
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        !!business.saml_provider
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/access-and-permission.svg"
      end

      sig { returns(String) }
      def help_link
        "#{GitHub.help_url}/admin/managing-iam/configuring-authentication-for-enterprise-managed-users/configuring-saml-single-sign-on-for-enterprise-managed-users"
      end

      sig { returns(String) }
      def help_link_text
        "Learn how to configure SAML SSO"
      end
    end
  end
end
