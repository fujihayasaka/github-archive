# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::FeatureFlagHelper
  class FeatureFlags
    HISTORICAL_BACKFILL_SCAN = :secret_scanning_historical_backfill_scan
    FEEDBACK_LINK = :secret_scanning_feedback_link
    PUSH_PROTECTION_FEEDBACK_BANNER = :secret_scanning_push_protection_feedback_banner
    PUSH_PROTECTION_USER_SETTINGS = :secret_scanning_push_protection_user_settings
    PUSH_PROTECTION_FOR_FPR = :secret_scanning_push_protection_for_fpr
    PUSH_PROTECTION_FOR_USERS_OPT_OUT = :secret_scanning_push_protection_for_users_opt_out
    CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI = :secret_scanning_udp_nlp
    GENERIC_SECRETS_BLOCK = :secret_scanning_generic_secrets_block
    PERSIST_RESULTS_FOR_PUBLIC_REPOS = :secret_scanning_write_results_for_public_scans
    USER_SCOPED_ANCESTOR_SCAN = :secret_scanning_user_scoped_ancestor_scan
    LOWER_CONFIDENCE_PATTERNS_DARK_SHIP = :secret_scanning_lower_confidence_patterns_dark_ship
    TOKEN_GROUPS_VALIDITY = :secret_scanning_token_groups_validity
    SCAN_PRIVATE_GISTS = :secret_scanning_scan_private_gists
    WIKI_INCREMENTAL_SCANS = :secret_scanning_wiki_incremental_scans
    WIKI_INCREMENTAL_SCANS_QUEUE = :secret_scanning_wiki_incremental_scans_queue_enabled
    WIKI_BACKFILL_SCANS = :secret_scanning_wiki_backfill_scans
    GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS = :secret_scanning_generic_secrets_in_security_configurations
    NON_PROVIDER_PATTERNS_ENABLEMENT_API = :secret_scanning_non_provider_patterns_enablement_api
    ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES = :secret_scanning_on_demand_checks_enabled_async_token_types
    VALIDITY_CHECKS_ENABLE_WITH_ORG_OR_ENTERPRISE = :secret_scanning_validity_checks_enable_with_org_or_enterprise
    CO_AUTHOR_ALERT_PERMISSIONS = :secret_scanning_co_author_alert_permissions
    OWNER_SERVICE_FLAGS_ON_ORG_ENABLEMENT = :secret_scanning_owner_service_flags_on_org_enablement
    GENERIC_SECRETS_FEEDBACK_LINK = :secret_scanning_generic_secrets_feedback_link
    WIKI_BACKFILL_ON_PUSH = :secret_scanning_wiki_backfill_on_public_repo_push
    SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS = :secret_scanning_show_single_alert_view_metadata_tags
    SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS = :secret_scanning_show_single_alert_view_related_alerts
    AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS = :ai_assisted_remediation_guidance_for_gh_pats
    DISPLAY_ALERT_PERMISSIONS = :secret_scanning_display_alert_permissions
    USE_DISPLAY_LOGIN_TWIRP = :secret_scanning_use_display_login_twirp
    AI_REMEDIATION_EXPERIMENTS = :secret_scanning_ai_remediation_experiments
    PLAID_UI_FILTERS = :secret_scanning_alert_plaid_ui_filters
    ASSESSMENT_RESCAN = :secret_risk_assessment_rescan
    PATTERN_CONFIG = :secret_scanning_pattern_config
    FIX_ENABLEMENT_CHECKS_FOR_SPLIT_SKU_TRIALS = :secret_scanning_fix_enablement_checks_for_split_sku_trials
    DISPLAY_FIRST_LOCATION_DETECTED = :secret_scanning_display_first_location_detected
    DISPLAY_HAS_MORE_LOCATIONS = :secret_scanning_display_has_more_locations
  end

  # Indicates whether a given feature flag is enabled for the given target,
  # either directly or through its hierarchy ie. this method will return true
  # for a repository if the feature flag is enabled for the repo's org or business
  sig { params(target: T.any(Repository, Organization, Business, User), feature_flag: Symbol).returns(T::Boolean) }
  def self.feature_flag_enabled_in_hierarchy?(target, feature_flag)
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

  # Indicates whether a given feature flag is enabled for the given target,
  # either directly or through its hierarchy ie. this method will return true
  # for a repository if the feature flag is enabled for the repo's org or business
  sig { params(target: T.any(Repository, Organization, Business, User), feature_flag: Symbol).returns(T::Boolean) }
  def feature_flag_enabled_in_hierarchy?(target, feature_flag)
    SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(target, feature_flag)
  end

  sig { params(entity: T.any(Repository, Business, User), current_user: T.nilable(User)).returns(T::Array[String]) }
  def get_tokens_api_feature_flags(entity, current_user: nil)
    flags = []
    flags << "stop_using_has_valid_locations"
    if feature_flag_enabled_in_hierarchy?(entity, FeatureFlags::GENERIC_SECRETS_BLOCK)
      flags << FeatureFlags::GENERIC_SECRETS_BLOCK
    end
    flags
  end
end
