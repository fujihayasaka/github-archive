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
    # in dotcom CI, MT mode is set dynamically in tests
    # so we need to be able to switch the authzd "config"/env based on the request
    if GitHub.multi_tenant_enterprise?
      attrs["#{DOTCOM_CI_ATTR_PREFIX}.is_multi_tenant_enterprise"] = "true"
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
        :cap_filter_consider_outside_collabs,
        :authzd_cap_enforcement_concurrent_policy_eval,
        :authzd_cap_enforcement_concurrent_policy_eval_non_failfast_only,
        :require_onboarding_for_pat_activation,
      ], instrumentation_properties: { "code.namespace": "authzd_test_helper" })
    end

    # global/darkship flags
    feature_flags = {
      "two_factor_cap_check_org_target_business": true, # will need this until we remove the hardcoded CI-mode check in authzd
      "enterprise_teams_migrate_from_cfb": GitHub.flipper[:enterprise_teams_migrate_from_cfb].enabled?,
      "copilot_metered_enterprise": GitHub.flipper[:copilot_metered_enterprise].enabled?,
      "unaffiliated_user_accounts": GitHub.flipper[:unaffiliated_user_accounts].enabled?,
      "saml_scope_private_resources_to_org": GitHub.flipper[:saml_scope_private_resources_to_org].enabled?,
      "sso_business_cred_authz_public_repos": false,
      "sso_same_business_cred_authz_private_repos": false,
      "ip_allowlist_user_level_enforcement": GitHub.flipper[:ip_allowlist_user_level_enforcement].enabled?,
      "intel_fork_ip_allowlist_org": true,
      "saml_org_ids_via_fg_pats": false,
      "authzd_cap_enforcement_concurrent_policy_eval": false,
      "authzd_cap_enforcement_concurrent_policy_eval_non_failfast_only": false,
      "oidc_cap_validator_caching_stop_checking_for_staff_ownership": GitHub.flipper[:oidc_cap_validator_caching_stop_checking_for_staff_ownership].enabled?,
      "apply_pat_limitations_to_ghes_and_emus": true,
      "ip_allowlist_org_apps_access_business_target": GitHub.flipper[:ip_allowlist_org_apps_access_business_target].enabled?,
      "bypass_pat_lifetime_policies_check": GitHub.flipper[:bypass_pat_lifetime_policies_check].enabled?,
    }

    # checked on the target
    if target && target != :no_target_for_conditional_access
      # target is org or business
      if target.instance_of?(Organization) || target.instance_of?(Business)
        biz = target.is_a?(Organization) ? target.async_business.sync : target
        feature_flags["saml_scope_private_resources_to_org"] = biz&.feature_enabled?(:saml_scope_private_resources_to_org) || GitHub.flipper[:saml_scope_private_resources_to_org].enabled?
        feature_flags["sso_business_cred_authz_public_repos"] = biz&.feature_enabled?(:sso_business_cred_authz_public_repos) || false
        feature_flags["disable_oidc_cap_cache"] = biz&.feature_enabled?(:disable_oidc_cap_cache) || false
      end

      # target is user
      if target.instance_of?(User)
        enabled = target.enterprise_managed_business&.feature_enabled?(:ip_allowlist_user_level_enforcement)
        feature_flags["ip_allowlist_user_level_enforcement"] = enabled unless enabled.nil?

        enabled = feature_flags["disable_oidc_cap_cache"] = target.enterprise_managed_business&.feature_enabled?(:disable_oidc_cap_cache)
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
      feature_flags["bypass_pat_lifetime_policies_check"] = GitHub.flipper[:bypass_pat_lifetime_policies_check].enabled?(user.programmatic_access)
    elsif user && user.using_personal_access_token?
      feature_flags["bypass_pat_lifetime_policies_check"] = GitHub.flipper[:bypass_pat_lifetime_policies_check].enabled?(user.oauth_access)
    end

    # checked on user actor
    if user && user.feature_enabled?(:cap_filter_consider_outside_collabs)
      feature_flags["cap_filter_consider_outside_collabs"] = true
    end
    if user && user.feature_enabled?(:sso_same_business_cred_authz_private_repos)
      feature_flags["sso_same_business_cred_authz_private_repos"] = true
    end
    if user && user.feature_enabled?(:saml_org_ids_via_fg_pats)
      feature_flags["saml_org_ids_via_fg_pats"] = true
    end
    if user && user.feature_enabled?(:require_onboarding_for_pat_activation)
      feature_flags["require_onboarding_for_pat_activation"] = true
    end

    if GitHub.multi_tenant_enterprise? && user&.enterprise_managed_business&.feature_enabled?(:emu_cap_staff_user)
      feature_flags["emu_cap_staff_user"] = true
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
