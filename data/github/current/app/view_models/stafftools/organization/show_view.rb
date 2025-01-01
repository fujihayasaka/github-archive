# typed: true
# frozen_string_literal: true

module Stafftools
  module Organization
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization
      include AuditLogHelper

      def show_two_factor_requirement_status?
        GitHub.auth.two_factor_authentication_enabled?
      end

      def two_factor_requirement_audit_log_query
        if driftwood_ade_query?(current_user)
          "#{organization.audit_log_kql_query} | where action in ('org.enable_two_factor_requirement', 'org.disable_two_factor_requirement')"
        else
          two_factor_requirement_query = \
            "(action:org.enable_two_factor_requirement OR action:org.disable_two_factor_requirement)"

          "(#{organization.audit_log_query} AND #{two_factor_requirement_query})"
        end
      end

      def two_factor_requirement_link_text
        if organization.two_factor_requirement_enabled?
          "2FA required"
        else
          "2FA not required"
        end
      end

      def saml_sso_octicon
        organization.saml_sso_enabled? || organization.business&.saml_sso_enabled? ? "shield-lock" : "x"
      end

      def saml_sso_enforcement_text
        if organization.business&.saml_sso_enabled?
          "SAML SSO enabled on owning enterprise"
        elsif organization.saml_sso_enforced?
          "SAML SSO enforced"
        elsif organization.saml_sso_enabled?
          "SAML SSO enabled"
        else
          "SAML SSO not enabled"
        end
      end

      def saml_sso_enforcement_link
        if organization.saml_sso_enabled? || organization.business&.saml_sso_enabled?
          helpers.link_to(
            saml_sso_enforcement_text,
            urls.stafftools_user_security_path(organization, anchor: "saml-settings"),
          )
        else
          saml_sso_enforcement_text
        end
      end

      def terms_of_service_audit_log_path
        query = "org_id:#{organization.id} action:*.update_terms_of_service"
        if driftwood_ade_query?(current_user)
          query = "webevents | where org_id == #{organization.id} and action endswith '.update_terms_of_service'"
        end
        urls.stafftools_audit_log_path(query: query)
      end

      def ssh_cas_link
        helpers.link_to(
          ssh_cas_text,
          urls.stafftools_user_ssh_keys_certificate_authorities_path(organization),
        )
      end

      def ssh_cas_text
        n = organization.ssh_certificate_authorities.count
        n = "No" if n == 0
        "#{n} SSH CAs configured"
      end

      def ip_allowlist_link
        helpers.link_to ip_allowlist_text, urls.stafftools_user_ip_allowlist_path(organization)
      end

      def ip_allowlist_text
        enabled = organization.ip_allowlist_enabled? ? "enabled" : "disabled"
        "IP allow list #{enabled}"
      end

      def audit_log_query
        if driftwood_ade_query?(current_user)
          organization.audit_log_kql_query
        else
          organization.audit_log_query
        end
      end

      def show_sdn_blocked_notice?
        organization.has_commercial_interaction_restriction?(feature_type: :terms_of_service_change)
      end

      def sdn_blocked_text
        ::TradeControls::Notices.terms_of_service_sdn_blocked_text(organization.trade_screening_status)
      end
    end
  end
end
