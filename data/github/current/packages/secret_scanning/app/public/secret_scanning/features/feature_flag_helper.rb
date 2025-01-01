# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::FeatureFlagHelper
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
    PERSIST_RESULTS_FOR_PUBLIC_REPOS = :secret_scanning_write_results_for_public_scans
    USER_SCOPED_ANCESTOR_SCAN = :secret_scanning_user_scoped_ancestor_scan
    LOWER_CONFIDENCE_PATTERNS_DARK_SHIP = :secret_scanning_lower_confidence_patterns_dark_ship
    TOKEN_GROUPS_VALIDITY = :secret_scanning_token_groups_validity
    SCAN_PRIVATE_GISTS = :secret_scanning_scan_private_gists
    WIKI_INCREMENTAL_SCANS = :secret_scanning_wiki_incremental_scans
    WIKI_INCREMENTAL_SCANS_QUEUE = :secret_scanning_wiki_incremental_scans_queue_enabled
    WIKI_BACKFILL_SCANS = :secret_scanning_wiki_backfill_scans
    SHOW_PAGE_SERIALIZE_LOCATION_REFACTOR = :secret_scanning_show_page_serialize_location_refactor
    VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS = :secret_scanning_validity_checks_in_security_configurations
    GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS = :secret_scanning_generic_secrets_in_security_configurations
    NON_PROVIDER_PATTERNS_ENABLEMENT_API = :secret_scanning_non_provider_patterns_enablement_api
    ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES = :secret_scanning_on_demand_checks_enabled_async_token_types
    VALIDITY_CHECKS_ENABLE_WITH_ORG_OR_ENTERPRISE = :secret_scanning_validity_checks_enable_with_org_or_enterprise
    CO_AUTHOR_ALERT_PERMISSIONS = :secret_scanning_co_author_alert_permissions
    OWNER_SERVICE_FLAGS_ON_ORG_ENABLEMENT = :secret_scanning_owner_service_flags_on_org_enablement
    CHECK_BYPASS_REVIEWER_IN_REPO_REQUEST_LIST = :secret_scanning_check_bypass_reviewer_in_repo_request_list
    GENERIC_SECRETS_FEEDBACK_LINK = :secret_scanning_generic_secrets_feedback_link
    WIKI_BACKFILL_ON_PUSH = :secret_scanning_wiki_backfill_on_public_repo_push
    DISPLAY_ORG_SS_BYPASS_REQUESTS_LIST = :display_org_ss_bypass_requests_list
    SECURITY_CENTER_SPLIT_SECRET_SCANNING_TAB_COUNTS = :security_center_split_secret_scanning_tab_counts
    SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS = :secret_scanning_show_single_alert_view_metadata_tags
    SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS = :secret_scanning_show_single_alert_view_related_alerts
    AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS = :ai_assisted_remediation_guidance_for_gh_pats
    DISPLAY_ALERT_PERMISSIONS = :secret_scanning_display_alert_permissions
    USE_DISPLAY_LOGIN_TWIRP = :secret_scanning_use_display_login_twirp
    AI_REMEDIATION_EXPERIMENTS = :secret_scanning_ai_remediation_experiments
    SHOW_CLOSURE_REQUESTS_ORG_SETTING = :show_secret_scanning_closure_requests_org_setting
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
