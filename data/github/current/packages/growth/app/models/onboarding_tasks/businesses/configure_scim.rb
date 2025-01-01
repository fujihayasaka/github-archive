# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class ConfigureSCIM < Base
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      sig { override.returns(String) }
      def title
        "Configure provisioning"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        enterprise_admins_path(business) if completed?
      end

      sig { returns(T.nilable(String)) }
      def task_link_text
        "View administrators" if completed?
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        number_of_additional_admins > 0 && business.external_provider_enabled?
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end

      sig { returns(T.nilable(String)) }
      def help_link
        if status == :pending_sso_configuration
          "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-with-scim/configuring-scim-provisioning-for-users#configuring-provisioning-for-enterprise-managed-users"
        elsif status == :pending_provisioning
          case provisioning_provider
          when :azure_ad
            "https://learn.microsoft.com/en-us/entra/identity/saas-apps/github-enterprise-managed-user-provisioning-tutorial#step-5-configure-automatic-user-provisioning-to-github-enterprise-managed-user"
          when :azure_ad_oidc
            "https://learn.microsoft.com/en-gb/entra/identity/saas-apps/github-enterprise-managed-user-oidc-provisioning-tutorial#step-5-configure-automatic-user-provisioning-to-github-enterprise-managed-user-oidc"
          when :okta
            "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-with-scim/configuring-scim-provisioning-with-okta"
          when :ping_federate
            "https://docs.pingidentity.com/r/en-us/pingfederate-github-emu-connector/pingfederate_github_connector_configure_pingfederate_for_provisioning_and_sso"
          else
            "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-with-scim/configuring-scim-provisioning-for-users#configuring-provisioning-for-other-identity-management-systems"
          end
        else
          nil
        end
      end

      sig { returns(T.nilable(String)) }
      def help_link_text
        if status == :pending_sso_configuration
          "Read our guide for configuring provisioning."
        elsif status == :pending_provisioning
          "Follow the steps to configure automatic provisioning."
        else
          nil
        end
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def status_label
        if status == :pending_sso_configuration
          { label: "Waiting for SSO configuration", color: :default, additional_text: "Unable to detect a tenant connection." }
        elsif status == :pending_provisioning
          { label: "Waiting for provisioning requests", color: :warning, additional_text: "#{provisioning_provider_name} is connected but no provisioning has started." }
        elsif status == :completed
          { label: "SCIM provisioning completed", color: :success, additional_text: "#{pluralize(number_of_additional_admins, "enterprise owner")} #{number_of_additional_admins > 1 ? "have" : "has"} been successfully provisioned." }
        else
          nil
        end
      end

      private

      sig { returns(Symbol) }
      def status
        if !business.external_provider.present?
          :pending_sso_configuration
        else
          if number_of_additional_admins == 0
            :pending_provisioning
          else
            :completed
          end
        end
      end

      sig { returns(Integer) }
      memoize def number_of_additional_admins
        business.find_emu_owners_except_first.count
      end

      sig { returns(Symbol) }
      memoize def provisioning_provider
        if business.external_provider.find_provider_type == :azure_ad && business.external_provider.is_a?(Business::OIDCProvider)
          :azure_ad_oidc
        else
          business.external_provider.find_provider_type
        end
      end

      sig { returns(String) }
      memoize def provisioning_provider_name
        case provisioning_provider
        when :azure_ad
          "Microsoft Entra ID"
        when :azure_ad_oidc
          "Microsoft Entra ID (OIDC)"
        when :okta
          "Okta"
        when :ping_federate
          "PingFederate"
        else
          "Your identity provider"
        end
      end
    end
  end
end
