# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class EnableSaml < Base
      sig { override.returns(String) }
      def title
        "Enable SAML single sign-on"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_security_path(organization, show_onboarding_guide_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        !!organization.saml_provider || verify_business_saml_provider
      end

      sig { returns(T::Boolean) }
      def verify_business_saml_provider
        return false unless business = organization.business
        !!business.saml_provider
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/access-and-permission.svg"
      end
    end
  end
end
