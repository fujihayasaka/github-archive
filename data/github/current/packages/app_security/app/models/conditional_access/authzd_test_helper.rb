# typed: true
# frozen_string_literal: true

module ConditionalAccess::AuthzdTestHelper
  def authzd_cap_dotcom_ci_attributes
    return unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    attrs = {}
    if VCR.cassettes.find { |c| c.name == "oidc/azure-cap-failure" }
      attrs["conditional.access.dotcom_ci.external_conditional_access_policy.refresh_token_request_response"] = "failure"
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
        :saml_scope_private_resources_to_org,
        :sso_business_cred_authz_public_repos,
        :sso_same_business_cred_authz_private_repos,
        :ip_allowlist_user_level_enforcement,
        :intel_fork_ip_allowlist_org,
        :saml_org_ids_via_fg_pats,
        :oidc_cap_validator_caching_stop_checking_for_staff_ownership,
        :disable_oidc_cap_cache,
      ], fetch_directly_from_adapter: false)
    end

    # global/darkship flags
    feature_flags = {
      "two_factor_cap_check_org_target_business": true, # will need this until we remove the hardcoded CI-mode check in authzd
      "enterprise_teams_migrate_from_cfb": GitHub.flipper[:enterprise_teams_migrate_from_cfb].enabled?,
      "copilot_metered_enterprise": GitHub.flipper[:copilot_metered_enterprise].enabled?,
      "unaffiliated_user_accounts": GitHub.flipper[:unaffiliated_user_accounts].enabled?,
      "saml_scope_private_resources_to_org": false,
      "sso_business_cred_authz_public_repos": false,
      "sso_same_business_cred_authz_private_repos": false,
      "ip_allowlist_user_level_enforcement": GitHub.flipper[:ip_allowlist_user_level_enforcement].enabled?,
      "intel_fork_ip_allowlist_org": true,
      "saml_org_ids_via_fg_pats": false,
      "oidc_cap_validator_caching_stop_checking_for_staff_ownership": GitHub.flipper[:oidc_cap_validator_caching_stop_checking_for_staff_ownership].enabled?,
    }

    # checked on the target
    if target && target != :no_target_for_conditional_access
      # target is org or business
      if target.instance_of?(Organization) || target.instance_of?(Business)
        biz = target.is_a?(Organization) ? target.async_business.sync : target
        feature_flags["saml_scope_private_resources_to_org"] = biz&.feature_enabled?(:saml_scope_private_resources_to_org) || false
        feature_flags["sso_business_cred_authz_public_repos"] = biz&.feature_enabled?(:sso_business_cred_authz_public_repos) || false
        feature_flags["disable_oidc_cap_cache"] = biz&.feature_enabled?(:disable_oidc_cap_cache) || false
      end

      # target is user
      if target.instance_of?(User)
        feature_flags["ip_allowlist_user_level_enforcement"] = target.enterprise_managed_business&.feature_enabled?(:ip_allowlist_user_level_enforcement) || false
        feature_flags["disable_oidc_cap_cache"] = target.enterprise_managed_business&.feature_enabled?(:disable_oidc_cap_cache) || false
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
    if user && user.feature_enabled?(:sso_same_business_cred_authz_private_repos)
      feature_flags["sso_same_business_cred_authz_private_repos"] = true
    end
    if user && user.feature_enabled?(:saml_org_ids_via_fg_pats)
      feature_flags["saml_org_ids_via_fg_pats"] = true
    end

    # this one is technically checked against an org in the policy
    # but the org is difficult to determine at this level of the request
    # since this is a long-lived feature flag that only applies to a couple of orgs,
    # this should do for now. Worst case, we may need to revisit this when enabling
    # science in CI for the IP allowlist policy. It may just mean we need to skip a test or two for
    # the science experiment at that point b/c it looks like there are only a couple of tests that manually disable this flag
    if GitHub.flipper[:intel_fork_ip_allowlist_org].enabled?
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
