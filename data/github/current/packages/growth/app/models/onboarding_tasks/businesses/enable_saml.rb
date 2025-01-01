# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class EnableSaml < Base
      sig { override.returns(String) }
      def title
        "Enable single sign-on"
      end

      sig { override.returns(String) }
      def task_link
        if business.feature_enabled?(:move_emu_sso_configuration_page)
          enterprise_single_sign_on_configuration_path(business, emu_onboarding: !completed?)
        else
          settings_security_enterprise_path(business, show_onboarding_guide_tip: true)
        end
      end

      sig { returns(String) }
      def task_link_text
        completed? ? "Manage SSO" : title
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        !!business.saml_provider || !!business.oidc_provider
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
        "#{GitHub.help_url}/admin/managing-iam/configuring-authentication-for-enterprise-managed-users"
      end

      sig { returns(String) }
      def help_link_text
        "Learn how to configure single sign-on"
      end
    end
  end
end
