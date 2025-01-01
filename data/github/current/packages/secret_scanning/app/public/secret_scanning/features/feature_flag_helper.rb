# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::FeatureFlagHelper
  extend T::Sig
  class FeatureFlags
    READ_PUBLIC_REPO_ALERTS = :secret_scanning_read_public_repo_alerts
    HISTORICAL_BACKFILL_SCAN = :secret_scanning_historical_backfill_scan
    FEEDBACK_LINK = :secret_scanning_feedback_link
    PUSH_PROTECTION_FEEDBACK_BANNER = :secret_scanning_push_protection_feedback_banner
    PUSH_PROTECTION_USER_SETTINGS = :secret_scanning_push_protection_user_settings
    PUSH_PROTECTION_FOR_FPR = :secret_scanning_push_protection_for_fpr
    PUSH_PROTECTION_FOR_USERS_OPT_OUT = :secret_scanning_push_protection_for_users_opt_out
    CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI = :secret_scanning_udp_nlp
    GENERIC_SECRETS_BLOCK = :secret_scanning_generic_secrets_block
    GENERIC_SECRETS_SCAN = :secret_scanning_generic_secrets_scan
    GENERIC_SECRETS_OWNER_ENABLEMENT = :secret_scanning_generic_secrets_owner_enablement
    GENERIC_SECRETS_ENTERPRISE_POLICY = :secret_scanning_generic_secrets_enterprise_policy
    PERSIST_RESULTS_FOR_PUBLIC_REPOS = :secret_scanning_write_results_for_public_scans
    USER_SCOPED_ANCESTOR_SCAN = :secret_scanning_user_scoped_ancestor_scan
    LOWER_CONFIDENCE_PATTERNS_DARK_SHIP = :secret_scanning_lower_confidence_patterns_dark_ship
    TOKEN_GROUPS_VALIDITY = :secret_scanning_token_groups_validity
    SCAN_PRIVATE_GISTS = :secret_scanning_scan_private_gists
    DISABLE_CUSTOM_PATTERN_LIVE_RELOAD = :disable_custom_pattern_live_reload
    WIKI_INCREMENTAL_SCANS = :secret_scanning_wiki_incremental_scans
    WIKI_BACKFILL_SCANS = :secret_scanning_wiki_backfill_scans
    SHOW_PAGE_SERIALIZE_LOCATION_REFACTOR = :secret_scanning_show_page_serialize_location_refactor
    VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS = :secret_scanning_validity_checks_in_security_configurations
    AUTOFIX = :secret_scanning_ai_autofix
    NON_PROVIDER_PATTERNS_ENABLEMENT_API = :secret_scanning_non_provider_patterns_enablement_api
    ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES = :secret_scanning_on_demand_checks_enabled_async_token_types
    VALIDITY_CHECKS_ENABLE_WITH_ORG_OR_ENTERPRISE = :secret_scanning_validity_checks_enable_with_org_or_enterprise
    CO_AUTHOR_ALERT_PERMISSIONS = :secret_scanning_co_author_alert_permissions
    OWNER_SERVICE_FLAGS_ON_ORG_ENABLEMENT = :secret_scanning_owner_service_flags_on_org_enablement
    CHECK_BYPASS_REVIEWER_IN_REPO_REQUEST_LIST = :secret_scanning_check_bypass_reviewer_in_repo_request_list
    GENERIC_SECRETS_FEEDBACK_LINK = :secret_scanning_generic_secrets_feedback_link
    ONE_CLICK_REPORT = :secret_scanning_one_click_report
    ONE_CLICK_REPORT_VERSION_REPORT = :secret_scanning_one_click_report_version_report
  end

  # Indicates whether a given feature flag is enabled for the given target,
  # either directly or through its hierarchy ie. this method will return true
  # for a repository if the feature flag is enabled for the repo's org or business
  sig { params(target: T.any(Repository, Organization, Business, User), feature_flag: Symbol).returns(T::Boolean) }
  def feature_flag_enabled?(target, feature_flag)
    if target.is_a?(Repository)
      return true if target.feature_enabled?(feature_flag)
      target = target.owner
    end

    if target.present? && target.is_a?(Organization)
      return true if target.feature_enabled?(feature_flag)
      target = target.business
    end

    if target.present? && target.is_a?(Business)
      return true if target.feature_enabled?(feature_flag)
    end

    if target.present? && target.is_a?(User)
      return true if target.feature_enabled?(feature_flag)
    end

    false
  end

  sig { params(entity: T.any(Repository, Business, User), current_user: T.nilable(User)).returns(T::Array[String]) }
  def get_tokens_api_feature_flags(entity, current_user: nil)
    flags = []
    flags << "stop_using_has_valid_locations"
    if feature_flag_enabled?(entity, FeatureFlags::GENERIC_SECRETS_BLOCK)
      flags << FeatureFlags::GENERIC_SECRETS_BLOCK
    end
    flags
  end
end
