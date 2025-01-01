# typed: true
# frozen_string_literal: true

module ConditionalAccess::AuthzdTestHelper
  DOTCOM_CI_ATTR_PREFIX = "conditional.access.dotcom_ci"

  def authzd_cap_dotcom_ci_attributes
    return unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    attrs = {}
    if VCR.cassettes.find { |c| c.name == "oidc/azure-cap-failure" }
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.external_conditional_access_policy.refresh_token_request_response"] = "failure"
    end
    # in dotcom CI, MT and GHES mode is set dynamically in tests
    # so we need to be able to switch the authzd "config"/env based on the request
    if GitHub.multi_tenant_enterprise?
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.is_multi_tenant_enterprise"] = "true"
    elsif GitHub.single_tenant_enterprise?
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.is_single_tenant_enterprise"] = "true"
    end

    # Enables Contractor Restrictions which is set dynamically through stubs in tests
    if GitHub.restrict_contractors_from_default_access_to_internal_repos?
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.restrict_contractors_from_default_access_to_internal_repos"] = "true"
    end

    if GitHub.auth.external_user?(nil)
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.stubbed_external_user"] = "true"
    end

    # If the disabled 2FA methods are stubbed in tests, we need to pass that info to Authzd
    if GitHub.respond_to?(:stub_authzd_two_factor_disallowed_methods)
      stubbed_methods = T.unsafe(GitHub).stub_authzd_two_factor_disallowed_methods
      if stubbed_methods
        method_string = stubbed_methods.to_a.join(",")
        attrs["#{DOTCOM_CI_ATTR_PREFIX}.stubbed_disabled_two_factor_methods"] = method_string
      end
    end

    # If the disabled 2FA methods are stubbed in tests, we need to pass that info to Authzd
    if GitHub.respond_to?(:stub_authzd_two_factor_enabled)
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.stubbed_two_factor_authentication_allowed"] = T.unsafe(GitHub).stub_authzd_two_factor_enabled.to_s
    end

    if GitHub.ip_allowlists_available?
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.stubbed_ip_allowlists_available"] = "true"
    end

    attrs
  end

  # this is a huge hack to enforce pre-resolution of feature flags
  # ONLY for tests while the feature-management team continues to
  # cutover test/CI to use the new feature flag system
  def github_features_header(target)
    return unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    target = target.first if target.is_a?(Array) || target.is_a?(Set)

    unless ApplicationController::PreloadFeatureFlagsDependency.skip_feature_preload_in_tests?
      FeatureFlag.vexi.preload([
        :enterprise_teams_migrate_from_cfb,
        :copilot_metered_enterprise,
        :unaffiliated_user_accounts,
        :saml_scope_private_resources_to_business,
        :sso_same_business_cred_authz_private_repos,
        :ip_allowlist_user_level_enforcement,
        :intel_fork_ip_allowlist_org,
        :disable_oidc_cap_cache,
        :cap_filter_consider_outside_collabs,
        :authzd_biz_teams_repo_readable_by,
        :authzd_biz_teams_repo_readable_by_science_only,
        :authzd_biz_has_all_repo_read,
        :authzd_biz_has_all_repo_read_science_only,
        :authzd_biz_teams_org_membership_check,
        :authzd_biz_teams_org_membership_check_science_only,
        :authzd_biz_org_ids_for_user,
        :authzd_biz_org_ids_for_user_science_only,
        :enterprise_teams_org_assignment,
      ], instrumentation_properties: { "code.namespace": "authzd_test_helper" })
    end

    # global/darkship flags
    feature_flags = {
      "two_factor_cap_check_org_target_business": true, # will need this until we remove the hardcoded CI-mode check in authzd
      "enterprise_teams_migrate_from_cfb": FeatureFlag.vexi.enabled?(:enterprise_teams_migrate_from_cfb, default: false),
      "copilot_metered_enterprise": FeatureFlag.vexi.enabled?(:copilot_metered_enterprise, default: false),
      "unaffiliated_user_accounts": FeatureFlag.vexi.enabled?(:unaffiliated_user_accounts, default: false),
      "saml_scope_private_resources_to_business": FeatureFlag.vexi.enabled?(:saml_scope_private_resources_to_business, default: false),
      "sso_same_business_cred_authz_private_repos": false,
      "ip_allowlist_user_level_enforcement": FeatureFlag.vexi.enabled?(:ip_allowlist_user_level_enforcement, default: false),
      "intel_fork_ip_allowlist_org": true,
      "apply_pat_limitations_to_ghes_and_emus": true,
      "ip_allowlist_org_apps_access_business_target": FeatureFlag.vexi.enabled?(:ip_allowlist_org_apps_access_business_target, default: false),
      "bypass_pat_lifetime_policies_check": FeatureFlag.vexi.enabled?(:bypass_pat_lifetime_policies_check, default: false),
      "authzd_biz_teams_repo_readable_by": FeatureFlag.vexi.enabled?(:authzd_biz_teams_repo_readable_by, default: false),
      "authzd_biz_teams_repo_readable_by_science_only": FeatureFlag.vexi.enabled?(:authzd_biz_teams_repo_readable_by_science_only, default: false),
      "authzd_biz_has_all_repo_read": FeatureFlag.vexi.enabled?(:authzd_biz_has_all_repo_read, default: false),
      "authzd_biz_has_all_repo_read_science_only": FeatureFlag.vexi.enabled?(:authzd_biz_has_all_repo_read_science_only, default: false),
      "authzd_biz_teams_org_membership_check": FeatureFlag.vexi.enabled?(:authzd_biz_teams_org_membership_check, default: false),
      "authzd_biz_teams_org_membership_check_science_only": FeatureFlag.vexi.enabled?(:authzd_biz_teams_org_membership_check_science_only, default: false),
      "authzd_biz_org_ids_for_user": FeatureFlag.vexi.enabled?(:authzd_biz_org_ids_for_user, default: false),
      "authzd_biz_org_ids_for_user_science_only": FeatureFlag.vexi.enabled?(:authzd_biz_org_ids_for_user_science_only, default: false),
      "saml_scim_only_access_allowed": true,
    }

    # checked on the target
    if target && target != :no_target_for_conditional_access
      # target is org or business
      if target.instance_of?(Organization) || target.instance_of?(Business)
        biz = target.is_a?(Organization) ? target.async_business.sync : target
        feature_flags["saml_scope_private_resources_to_business"] = biz&.feature_flag_enabled?(:saml_scope_private_resources_to_business, default: false) || FeatureFlag.vexi.enabled?(:saml_scope_private_resources_to_business, default: false)
        feature_flags["disable_oidc_cap_cache"] = biz&.feature_flag_enabled?(:disable_oidc_cap_cache, default: false) || false
        feature_flags["enterprise_teams_org_assignment"] = biz&.erp_feature_enabled?(:enterprise_teams_org_assignment)
      end

      # target is user
      if target.instance_of?(User)
        enabled = target.enterprise_managed_business&.feature_flag_enabled?(:ip_allowlist_user_level_enforcement, default: false)
        feature_flags["ip_allowlist_user_level_enforcement"] = enabled unless enabled.nil?

        enabled = feature_flags["disable_oidc_cap_cache"] = target.enterprise_managed_business&.feature_flag_enabled?(:disable_oidc_cap_cache, default: false)
        feature_flags["disable_oidc_cap_cache"] = enabled unless enabled.nil?
      end
    end

    # checked on actor
    # checked on user actor
    user = if a = authzd_cap_actor
      if a.is_a?(User)
        a
      else
        a.respond_to?(:user) ? a.user : nil
      end
    end

    if user && user.using_auth_via_user_programmatic_access?
      feature_flags["bypass_pat_lifetime_policies_check"] = FeatureFlag.vexi.enabled?(:bypass_pat_lifetime_policies_check, user.programmatic_access, default: false)
    elsif user && user.using_personal_access_token?
      feature_flags["bypass_pat_lifetime_policies_check"] = FeatureFlag.vexi.enabled?(:bypass_pat_lifetime_policies_check, user.oauth_access, default: false)
    end

    # checked on user actor
    if user && user.feature_flag_enabled?(:cap_filter_consider_outside_collabs, default: false)
      feature_flags["cap_filter_consider_outside_collabs"] = true
    end
    if user && user.feature_flag_enabled?(:sso_same_business_cred_authz_private_repos, default: false)
      feature_flags["sso_same_business_cred_authz_private_repos"] = true
    end

    # this one is technically checked against an org in the policy
    # but the org is difficult to determine at this level of the request
    # since this is a long-lived feature flag that only applies to a couple of orgs,
    # this should do for now. Worst case, we may need to revisit this when enabling
    # science in CI for the IP allowlist policy. It may just mean we need to skip a test or two for
    # the science experiment at that point b/c it looks like there are only a couple of tests that manually disable this flag
    if FeatureFlag.vexi.enabled?(:intel_fork_ip_allowlist_org, default: false)
      feature_flags["intel_fork_ip_allowlist_org"] = true
    end

    feature_flags = feature_flags.map do |k, v|
      "#{k}:#{!!v ? "1" : "0"}"
    end
    Base64.strict_encode64(JSON.dump(feature_flags))
  end

  # this is a hack to send the capabilities of an application to Authzd
  # ONLY if the actor has an application, the capabilities will be calculated
  # ONLY for tests while we don't have a better solution for syncing capabilities
  def github_capabilities_header
    return unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    application = case a = authzd_cap_actor
    when Integration, OauthApplication
      a
    when Bot
      a.integration
    when User
      a.oauth_access&.application
    else
      nil
    end

    return unless application

    capabilities = {
      saml_sso_required: Apps::Privileged.capable?(:saml_sso_required, app: application),
      skip_emu_ownership_cap: Apps::Privileged.capable?(:skip_emu_ownership_cap, app: application),
      skip_tenant_verification_cap: Apps::Privileged.capable?(:skip_tenant_verification_cap, app: application),
      skip_enterprise_access_verification_cap: Apps::Privileged.capable?(:skip_enterprise_access_verification_cap, app: application),
      ip_allowlist_exempt_for_internal_apis: Apps::Privileged.capable?(:ip_allowlist_exempt_for_internal_apis, app: application),
      ip_allowlist_exempt: Apps::Privileged.capable?(:ip_allowlist_exempt, app: application),
      installed_globally: Apps::Privileged.capable?(:installed_globally, app: application),
    }

    capabilities = capabilities.map do |k, v|
      "#{k}:#{!!v ? "1" : "0"}"
    end
    Base64.strict_encode64(JSON.dump(capabilities))
  end

  def authzd_cap_actor
    Kernel.raise("authzd_cap_actor must be implemented in including types")
  end
end
