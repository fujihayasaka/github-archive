# typed: true
# frozen_string_literal: true

module Orgs
  module SecuritySettings
    class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization, :business, :saml_provider, :current_external_identity, :team_sync_setup_flow
      include GitHub::Memoizer
      include PlatformHelper

      def sso_url
        business&.saml_provider&.sso_url.presence || saml_provider&.sso_url
      end

      def issuer
        business&.saml_provider&.issuer.presence || saml_provider&.issuer
      end

      def idp_certificate
        business&.saml_provider&.idp_certificate.presence || saml_provider&.idp_certificate
      end

      def two_factor_requirement_checkbox_disabled?
        two_factor_requirement_form_disabled?
      end

      def two_factor_requirement_form_disabled?
        !GitHub.auth.two_factor_org_requirement_allowed? || !current_user.two_factor_authentication_enabled? ||
            two_factor_required_policy?
      end

      def two_factor_secure_methods_checkbox_disabled?
        !GitHub.auth.two_factor_org_requirement_allowed? || !current_user.two_factor_authentication_enabled? ||
            two_factor_disallowed_methods_policy?
      end

      def two_factor_enforcement_form_disabled?
        two_factor_requirement_checkbox_disabled? && two_factor_secure_methods_checkbox_disabled?
      end

      def disable_submit_button?
        two_factor_enforcement_form_disabled? ||
          enforcing_two_factor_requirement?
      end

      def two_factor_secure_methods_required?
        insecure_two_factor_methods_disallowed?
      end

      def two_factor_requirement_needs_confirmation?
        organization.can_disallow_two_factor_methods? ||
        (!organization.members_without_2fa_allowed? || organization.outside_collaborators.any?) ||
        (!two_factor_requirement_enabled? && affiliated_users_with_two_factor_disabled_exist?)
      end

      def disabled_form_reason
        if organization.can_disallow_two_factor_methods?
          if !GitHub.auth.two_factor_authentication_enabled?
            { reason: "Built-in two-factor authentication is disabled on your instance.", icon: :"shield-slash" }
          elsif two_factor_required_policy? || two_factor_disallowed_methods_policy?
            { reason: disabled_by_administrators_link, icon: :"shield-lock" }
          elsif GitHub.auth.builtin_auth_fallback? && !GitHub.auth.two_factor_org_requirement_allowed?
            { reason: "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed.", icon: :"shield-slash" }
          elsif !current_user.two_factor_authentication_enabled?
            link = helpers.link_to("your account", urls.settings_security_path, class: "Link--inTextBlock")
            { reason: helpers.safe_join(["This setting requires two-factor authentication on ", link, "."]), icon: :shield }
          end
        else
          if !GitHub.auth.two_factor_authentication_enabled?
            "Built-in two-factor authentication is disabled on your instance."
          elsif two_factor_required_policy?
            disabled_by_administrators_link
          elsif GitHub.auth.builtin_auth_fallback? && !GitHub.auth.two_factor_org_requirement_allowed?
            "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed."
          elsif !current_user.two_factor_authentication_enabled?
            link = helpers.link_to("your account", urls.settings_security_path, class: "Link--inTextBlock")
            helpers.safe_join(["This setting requires two-factor authentication on ", link, "."])
          end
        end
      end

      delegate :two_factor_requirement_enabled?,
        :two_factor_requirement_disabled?,
        :affiliated_users_with_two_factor_disabled_exist?,
        :enforcing_two_factor_requirement?,
        :two_factor_required_policy?,
        :affiliated_user_ids_with_two_factor_disabled_counts,
        :outside_collaborators_with_two_factor_disabled,
        :outside_collaborators_with_two_factor_disabled_count,
        :affiliated_users_with_two_factor_disabled_scopes,
        :insecure_two_factor_methods_disallowed?,
        :two_factor_disallowed_methods_policy?,
        to: :organization

      def two_factor_requirement_disabled_and_needs_confirmation?
        two_factor_requirement_disabled? && affiliated_users_with_two_factor_disabled_exist?
      end

      def organization_saml_settings_saved?
        sso_url.present? && idp_certificate.present?
      end

      # Public: Method to check if the changes to SAML SSO configuration need to be disabled.
      #    It is very important that any changes to SSO are done through a delete of an existing provider
      #    and addition of a new one.  By updating the SSO settings customers were running into situations
      #    where single user had multiple external identity records which is not allowed and were experiencing
      #    failures.  This fix is important in case of moving from one tenant to another or switching IdP providers.
      #
      # Returns Boolean
      def saml_sso_configuration_changes_readonly?
        organization.saml_provider.present? && organization_saml_settings_saved?
      end

      def business_saml_settings_saved?
        return false unless business && business.saml_provider

        business.saml_provider.sso_url.present? &&
          business.saml_provider.idp_certificate.present?
      end

      def show_saml_settings?
        return true if organization_saml_settings_saved?

        saml_provider && saml_provider.errors.any?
      end

      def saml_enforced?
        organization.external_identity_session_owner.saml_sso_enforced?
      end

      def unlinked_saml_members
        @unlinked_saml_members ||= organization.unlinked_saml_members
      end

      def saml_test_settings
        saml_provider if saml_provider.is_a?(Organization::SamlProviderTestSettings)
      end

      def saml_testing?
        !!saml_test_settings
      end

      def saml_test_failure?
        saml_testing? && saml_test_settings.failure?
      end

      def saml_test_success?
        saml_testing? && saml_test_settings.success?
      end

      def saml_test_errors
        return unless saml_testing?

        saml_test_settings.message ||
          "invalid settings"
      end

      def disallow_sso_enforcement?
        current_external_identity.nil? || business_sso_configured?
      end

      # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-MessageAuthentication
      DEFAULT_SIGNATURE_METHOD = SamlProviderAlgorithms::DEFAULT_SIGNATURE_METHOD
      SIGNATURE_METHOD_OPTIONS = {
        "RSA-SHA1"   => "http://www.w3.org/2001/04/xmldsig-more#rsa-sha1",
        "RSA-SHA256" => "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        "RSA-SHA384" => "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384",
        "RSA-SHA512" => "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512",
      }

      def signature_method
        SIGNATURE_METHOD_OPTIONS.values.include?(saml_provider&.signature_method.to_s) ? saml_provider&.signature_method.to_s : DEFAULT_SIGNATURE_METHOD
      end

      def signature_method_label
        SIGNATURE_METHOD_OPTIONS.key(signature_method) ||
          SIGNATURE_METHOD_OPTIONS.key(DEFAULT_SIGNATURE_METHOD)
      end

      def saml_signature_method_options
        SIGNATURE_METHOD_OPTIONS
      end

      # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-MessageDigest
      DEFAULT_DIGEST_METHOD = SamlProviderAlgorithms::DEFAULT_DIGEST_METHOD
      DIGEST_METHOD_OPTIONS = {
        "SHA1"   => "http://www.w3.org/2000/09/xmldsig#sha1",
        "SHA256" => "http://www.w3.org/2001/04/xmlenc#sha256",
        "SHA384" => "http://www.w3.org/2001/04/xmlenc#sha384",
        "SHA512" => "http://www.w3.org/2001/04/xmlenc#sha512",
      }

      def digest_method
        DIGEST_METHOD_OPTIONS.values.include?(saml_provider&.digest_method.to_s) ? saml_provider&.digest_method.to_s : DEFAULT_DIGEST_METHOD
      end

      def digest_method_label
        DIGEST_METHOD_OPTIONS.key(digest_method) ||
          DIGEST_METHOD_OPTIONS.key(DEFAULT_DIGEST_METHOD)
      end

      def saml_digest_method_options
        DIGEST_METHOD_OPTIONS
      end

      def sso_url_error
        saml_provider && saml_provider.errors[:sso_url].first
      end

      def issuer_error
        saml_provider && saml_provider.errors[:issuer].first
      end

      def idp_certificate_error
        saml_provider && saml_provider.errors[:idp_certificate].first
      end

      def saml_session_length_error
        organization&.saml_provider && organization.saml_provider.errors[:session_length_in_minutes].first
      end

      def disabled_by_administrators_link
        if organization.can_disallow_two_factor_methods?
          link = helpers.link_to("#{business&.name || "enterprise administrators"}", GitHub.business_accounts_help_url, class: "Link--inTextBlock")
          helpers.safe_join(["This setting is enabled by ", link, "."])
        else
          link = helpers.link_to("required by enterprise administrators", GitHub.business_accounts_help_url)
          helpers.safe_join(["This setting has been ", link, "."])
        end
      end

      def business_sso_configured?
        organization.sso_enabled_on_business?
      end

      def business_emu_configured?
        business&.enterprise_managed_user_enabled?
      end

      def show_team_sync_settings?
        organization.business_plus? && !business_sso_configured? && !business_emu_configured?
      end

      def show_automated_security_fix_settings?
        GitHub.dependabot_enabled?
      end

      def supported_team_sync_provider?
        team_sync_provider_candidate&.supported_for_org?(organization)
      end

      def disallow_team_sync_setup?
        current_external_identity.nil?
      end

      def enable_team_sync_settings?
        organization_saml_settings_saved? &&
        supported_team_sync_provider?
      end

      def team_sync_status
        # If we're running a SAML test, it's OK to default to the organization's
        # provider
        return unless saml_provider.present? || saml_testing?

        count = organization.async_externally_managed_teams.sync&.count

        if count
          "#{count} #{"team".pluralize(count)} managed in #{team_sync_provider_type_label}."
        end
      end

      def team_sync_activity_link
        query = { q: "actor:github-team-synchronization[bot] action:team.add_member action:team.remove_member" }
        helpers.link_to("View activity", urls.settings_org_audit_log_path(organization, query))
      end

      IDENTITY_PROVIDER_OPTIONS = {
        "unknown" => "Unknown",
        "azuread" => "Entra ID",
        "okta" => "Okta",
      }

      def show_enable_team_sync_button?
        ::TeamSync::SetupFlow::STARTING_STATES.include?(team_sync_setup_flow.status) ||
          team_sync_setup_flow.status.nil?
      end

      def show_team_sync_assignment_review_available?
        ::TeamSync::SetupFlow::APPROVAL_STATE == team_sync_setup_flow.status
      end

      def team_sync_enabled?
        team_sync_setup_flow.tenant.team_sync_enabled?
      end

      def team_sync_provider_type_label
        IDENTITY_PROVIDER_OPTIONS[provider_type]
      end

      def team_sync_provider_id
        team_sync_setup_flow.provider_id
      end

      def show_ssh_cas?
        organization.ssh_enabled?
      end

      def show_ip_allowlist?
        GitHub.ip_allowlists_available?
      end

      def ip_allowlist_entries(query: nil, page: nil)
        return IpAllowlistEntry.none unless GitHub.ip_allowlists_available?
        organization
          .filtered_ip_allowlist_entries(query: query)
          .paginate(page: page)
      end

      def installed_app_ip_allowlist_entries(query: nil, page: nil)
        return IpAllowlistEntry.none unless GitHub.ip_allowlists_available?
        organization
          .filtered_installed_app_ip_allowlist_entries(query: query)
          .paginate(page: page)
      end

      def installed_app_ip_allowlist_entries_info
        if installed_app_ip_allowlist_entries.any?
          names = installed_app_ip_allowlist_entries.map { |e| e.owner.name }.uniq.to_sentence
          "The following GitHub Apps you have installed define their own IP allow list entries: #{names}"
        else
          "You have no installed GitHub Apps that define their own IP allow list entries."
        end
      end

      def ssh_cas
        SshCertificateAuthority.usable_for(organization)
      end

      def team_sync_install_path
        raise "SAML Provider is required" unless saml_provider

        case provider_type&.to_sym
        when :azuread
          urls.team_sync_install_path(organization)
        when :okta
          if okta_team_sync?
            urls.new_orgs_team_sync_okta_credentials_path(organization)
          else
            raise "Unsupported provider type for issuer #{saml_provider.issuer}"
          end
        else
          raise "Unsupported provider type for issuer #{saml_provider.issuer}"
        end
      end

      def okta_team_sync?
        provider_type&.to_sym == :okta
      end

      def unlinked_members_count
        @unlinked_members_count ||= unlinked_saml_members.size
      end

      # Showing too many will cause the page to timeout. We pick an arbitrary
      # number to cutoff at
      def show_unlinked_members?
        # dont count linked/unlinked members if SAML is configured at enterprise level as this option is not available for org-admins
        return false if business_sso_configured?
        unlinked_members_count <= 25
      end

      def can_promote_enterprise?
        return false if GitHub.single_business_environment?
        return false unless organization
        return false unless current_user
        return false unless organization.adminable_by?(current_user)

        organization.plan.free? || organization.plan.business?
      end

      def saml_session_length
        organization&.saml_provider&.session_length_in_minutes
      end

      def users_with_two_factor_disabled_count
        affiliated_user_ids_with_two_factor_disabled_counts
      end

      def users_with_two_factor_disabled(limit: 100)
        return @users_with_two_factor_disabled if defined?(@users_with_two_factor_disabled)
        users_with_two_factor_disabled = Set.new
        remainder = limit

        affiliated_users_with_two_factor_disabled_scopes(limit: limit).each do |scope|
          users = scope.limit(remainder)
          users_with_two_factor_disabled.merge users
          remainder = remainder - users.size
          break if remainder <= 0
        end

        @users_with_two_factor_disabled = users_with_two_factor_disabled.to_a
      end

      # no need to distinguish OCs after https://github.com/github/authorization/issues/4526
      memoize def tmp_collaborators_with_two_factor_disabled_count
        outside_collaborators_with_two_factor_disabled_count
      end

      def private_forks_count_for(user)
        @private_fork_counts ||= Repository.organization_member_private_forks(
          organization, users_with_two_factor_disabled).group(:owner_id).count

        @private_fork_counts[user.id] || 0
      end

      def show_private_forks_count_for?(user)
        private_forks_count_for(user) > 0
      end

      def prevented_from_removal_due_to_enterprise_team?(user)
        organization.prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team)
      end

      private

      # This is the potential team sync provider, based on the SAML issuer
      def team_sync_provider_candidate
        @team_sync_provider_candidate ||= ::TeamSync::Provider.detect(issuer: saml_provider.issuer)
      end

      # Derive type from SAML issuer (instead of tenants that may have
      # been created from older SAML configurations).
      def provider_type
        team_sync_provider_candidate&.type
      end
    end
  end
end
