# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class SecurityView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::StatusChecklist

      attr_reader :user

      def business_sso_configured?
        user.organization? && user.business&.external_provider_enabled?
      end

      def show_linked_saml_identity?
        user.business.present? && user.external_identity.present? && user.external_identity.provider.target == user.business
      end

      def show_team_sync_settings?
        user.business_plus?
      end

      def team_sync_enabled?
        !!tenant&.team_sync_enabled?
      end

      def team_sync_forbid_organization_invites?
        !!tenant&.forbid_organization_invites
      end

      def business_team_sync_enabled?
        user.organization? && user.business&.team_sync_enabled?
      end

      def missing_team_sync_integration?
        user.integration_installations.map(&:integration).none?(&:group_syncer_github_app?)
      end

      def org_with_no_admins?
        user.organization? && user.admins.none?
      end

      def team_sync_provider_type_label
        ::Orgs::SecuritySettings::IndexView::IDENTITY_PROVIDER_OPTIONS[tenant&.provider_type]
      end

      def team_sync_provider_id
        tenant&.provider_id
      end

      def page_title
        "#{user.login} - Security"
      end

      def audit_query
        query = "user_id:#{user.id} OR actor_id:#{user.id}"
        if user.organization?
          "((_exists_:org AND org_id:#{user.id}) OR #{query})"
        else
          "(#{query})"
        end
      end

      def audit_kql_query
        query = "webevents | where (user_id == #{user.id} or actor_id == #{user.id})"
        if user.organization?
          query << " or (isnotempty(org) and org_id == #{user.id})"
        end
        query
      end

      def show_legacy_log?
        user.staff_notes.any?
      end

      def two_factor_status
        if user.two_factor_authentication_enabled?
          status_li(true, "2FA enabled")
        else
          status_li(false, "2FA not enabled")
        end
      end

      def two_factor_recovery_status
        if user.two_factor_authentication_enabled?
          if user.two_factor_credential.recovery_codes_viewed?
            status_li(true, "2FA recovery codes viewed")
          else
            status_li(:error, "2FA recovery codes not viewed")
          end
        end
      end

      def two_factor_fallback_status
        return nil unless GitHub.two_factor_sms_enabled?

        if user.two_factor_authentication_enabled?
          if user.two_factor_backup_sms_number
            status_li(true, "Fallback number set")
          else
            status_li(:error, "Fallback number not set")
          end
        end
      end

      def is_recovery_request_enabled?
        !GitHub.enterprise?
      end

      def current_recovery_request?
        current_2fa_recovery_request.present?
      end

      def current_2fa_recovery_request
        return nil if !is_recovery_request_enabled?

        @current_2fa_recovery_request ||= TwoFactorRecoveryRequest.find_for_staff_review(user)
      end

      def recovery_request_verified_details
        return nil unless current_recovery_request?
        return nil if current_2fa_recovery_request.review_state == :evidence_missing

        "#{current_2fa_recovery_request.secondary_evidence_method} '#{current_2fa_recovery_request.secondary_evidence_identifier}'"
      end

      def recovery_request_review
        return nil unless current_recovery_request?
        @recovery_review = TwoFactorRecoveryRequestReview.mget([current_2fa_recovery_request.id]) if @recovery_review.nil?
        @recovery_review[current_2fa_recovery_request.id] if !@recovery_review.empty?
      end

      def recovery_request_ready_for_review?
        return false unless current_recovery_request?
        return false if current_2fa_recovery_request.review_state == :incomplete
        return false if current_2fa_recovery_request.review_state == :reviewed_by_staff

        true
      end

      def show_two_factor_recovery_email_list?
        return false unless recovery_request_ready_for_review?

        manual_email_selection_required = recovery_request_review.present? ? recovery_request_review["type"] == "email_status" : true

        user.emails.many? && manual_email_selection_required
      end

      # The rejection here is handled in two phases
      # First we reject users.noreply.github.com without checking for generic domains.
      # This prevents us from inaccurately removing a primary or backup as generic, and eliminates the potential
      # for that type of email to show up high in the List
      # Then we drop generics once primary and backup have been procured.
      def two_factor_recovery_emails
        mails = user.emails.primary_first.to_a.reject { |t| t.email =~ /users.noreply.github.com\z/ }
        emails = mails[1]&.backup_role? ? mails.shift(2) : mails.shift(1)

        unless mails.empty?
          mails.reject! { |t| UserEmail.generic_domain?(t.email) }
          verified, unverified = mails.partition(&:verified?)
          emails.concat(verified, unverified)
        end

        emails
      end

      def show_two_factor_sms_numbers?
        GitHub.two_factor_sms_enabled? && user.two_factor_authentication_enabled?
      end

      def two_factor_type
        if user.two_factor_authentication_enabled?
          options = []
          options << "Authenticator app" if user.two_factor_configured_with?(:app)
          options << "SMS message" if user.two_factor_configured_with?(:sms)
          options.join(" and ")
        else
          "disabled"
        end
      end

      def two_factor_sms?
        user.two_factor_configured_with?(:sms)
      end

      def fallback_number
        user.two_factor_backup_sms_number || "none"
      end

      def fallback_number?
        user.two_factor_backup_sms_number&.present?
      end

      # Does this user explicitly have an SMS provider set?
      #
      # Returns a Boolean
      def sms_provider_set?
        user.two_factor_sms_provider.present?
      end

      # The SMS provider that will be used to send SMS messages to this user.
      #
      # Returns a String
      def sms_provider
        if user.two_factor_sms_provider
          user.two_factor_sms_provider
        else
          GitHub::Messaging.providers_for_env.first.provider_name.to_s
        end
      end

      # The "other" SMS provider that is not currently being used to send SMS
      # messages to this user.
      #
      # Returns a String
      def other_sms_provider
        if GitHub::Messaging.providers_for_env.first.provider_name.to_s == sms_provider
          GitHub::Messaging.providers_for_env.last.provider_name.to_s
        else
          GitHub::Messaging.providers_for_env.first.provider_name.to_s
        end
      end

      # Does this user have any web or mobile sessions?
      def sessions?
        sessions.any? || mobile_sessions?
      end

      def mobile_sessions?
        active_mobile_sessions.any?
      end

      def active_mobile_sessions
        mobile_sessions
      end

      def grouped_web_sessions
        sessions.group_by { |session| session.session.state }
      end

      def sessions_with_locked_ip
        sessions.uniq { |s| s.ip }.select { |s| AuthenticationLimit.at_any?(web_ip: s.ip) }
      end

      def expiration(data)
        AuthenticationLimit.longest_expiration(data)
      end

      def show_org_application_policy?
        GitHub.oauth_application_policies_enabled? && user.organization?
      end

      def org_restricts_oauth_applications?
        user.organization? && user.restricts_oauth_applications?
      end

      def org_approved_applications
        user.oauth_application_approvals
          .approved.includes(application: :user)
          .reject { |approval| approval.application.user.blank? }
      end

      def org_applications_pending_approval
        user.oauth_application_approvals
          .pending_approval.includes(application: :user)
          .reject { |approval| approval.application.user.blank? }
      end

      def org_denied_applications
        user.oauth_application_approvals
          .denied.includes(application: :user)
          .reject { |approval| approval.application.user.blank? }
      end

      def org_blocked_applications
        user
          .oauth_application_approvals
          .blocked
          .includes(application: :user)
          .reject { |approval| approval.application.user.blank? }
      end

      def application_access_policy_audit_query
        return nil unless user.organization?

        audit_query + " AND action:org.*oauth_app*"
      end

      def application_access_policy_audit_kql_query
        return nil unless user.organization?

        audit_kql_query + " and action matches regex 'org.*oauth_app*'"
      end

      def show_password_randomization?
        return false if GitHub.auth.external?
        return false unless user.user?
        true
      end

      def show_saml_provider?
        user.organization? && (user.saml_sso_enabled? || user.saml_provider.present? || user.business&.saml_sso_enabled?)
      end

      def organization_sso_configured?
        user.organization? && (user.saml_sso_enabled? || user.saml_provider.present?)
      end

      def show_external_authentication_attributes?
        external_mapping.present? && !GitHub.global_business&.enterprise_server_scim_enabled?
      end

      def show_external_identities?
        # 1:1 identity relationships are rendered in the user overview page
        return false if user.is_enterprise_managed? || GitHub.single_business_environment?
        user.external_identities.any?
      end

      def get_external_identities
        user.external_identities.filter_map do |external_identity|
          external_identity.provider.target if external_identity.provider.present?
        end
      end

      def external_authentication_attributes
        return {} unless external_mapping

        case external_mapping
        when SamlMapping
          {
            "NameID" => external_mapping.name_id,
            "NameID format" => external_mapping.name_id_format,
          }
        when CasMapping
          {
            "CAS username" => external_mapping.username,
          }
        when LdapMapping
          {
            "Distinguished name (DN)" => external_mapping.dn,
          }
        end
      end

      def name_id
        external_mapping&.name_id
      end

      # Public: can the site admin edit NameID of the user?
      #
      # Returns: Boolean.
      def show_name_id_edit?
        show_external_authentication_attributes? && external_mapping.is_a?(SamlMapping)
      end

      private

      def external_mapping
        GitHub.auth.external_mapping(user)
      end

      def tenant
        user.try(:team_sync_tenant)
      end

      def sessions
        @sessions ||= user.sessions.map { |s| Session.new s }
      end

      def mobile_sessions
        @mobile_sessions ||= user.display_mobile_device_auth_keys.map do |ms|
          oauth_access = OauthAccessTokens.domain.by_id(ms.oauth_access_id)

          MobileSession.new(ms, oauth_access)
        end
      end

      class MobileSession
        include MobileDeviceHelper

        attr_reader :oauth_access
        attr_accessor :mobile_session
        delegate :id, :device_name, :created_at_time, to: :mobile_session

        def initialize(mobile_session = nil, oauth_access = nil)
          @mobile_session = mobile_session
          @oauth_access = oauth_access
        end

        def device_model
          get_device_model(mobile_session.device_model)
        end

        def formatted_created_at
          oauth_access&.created_at&.strftime("%b %-d, %Y")
        end

        def last_authenticated_at
          if mobile_session.last_used_at_time&.seconds
            Time.at(mobile_session&.last_used_at_time&.seconds).strftime("%b %-d, %Y")
          end
        end

        def details
          {
            ID: mobile_session.id,
            Name: mobile_session&.device_name || "Unknown",
            Model: device_model,
            Registered: formatted_created_at || "Unknown",
            "Last Used For Authentication": last_authenticated_at || "Never used",
            "Last Accessed": oauth_access&.accessed_at&.strftime("%b %-d, %Y") || "Never used",
          }
        end
      end

      class Session
        attr_accessor :session
        delegate :active?, :sudo?, :state, :id, :created_at, :ip, :time_zone_name, to: :session

        def initialize(session = nil)
          @session = session
        end

        def os
          return nil unless session.ua
          [session.ua.platform.name, session.ua.platform.version].join(" ")
        end

        def mobile?
          return false unless session.ua
          !!session.ua.device.mobile?
        end

        def short_os
          return "Unknown" unless session.ua
          case os
          when /iPhone/;        "iOS"
          when /Macintosh/;     "OSX"
          when /Android/;       "Android"
          when "Windows 8";     "Win8"
          when "Windows 7";     "Win7"
          when "Windows Vista"; "Vista"
          when /Windows XP/;    "WinXP"
          when /Windows/;       "Win"
          when /Linux/;         "Linux"
          else;                 os
          end
        end

        def details
          expiry_key = session.expired? ? "Expired at" : "Expires at"
          {
            :ID => session.id,
            :State => session.state,
            :RevokedReason => session.revoked_reason,
            :Impersonated => session.impersonated? ? session.impersonator.login : false,
            :Created => session.created_at,
            "Last accessed" => session.accessed_at,
            expiry_key => session.expire_time,
            :Browser => session.ua&.name || "Unknown",
            :OS => os || "Unknown",
            :Mobile => mobile?,
            "User Agent" => session.user_agent,
            :IP => session.ip,
            :TimeZone => session.time_zone_name,
            :Geolocation => session.location.inspect,
          }
        end
      end
    end
  end
end
