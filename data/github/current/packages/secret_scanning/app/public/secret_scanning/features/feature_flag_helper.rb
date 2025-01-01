# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::FeatureFlagHelper
  class FeatureFlags
    FEEDBACK_LINK = :secret_scanning_feedback_link
    PUSH_PROTECTION_FOR_FPR = :secret_scanning_push_protection_for_fpr
    PUSH_PROTECTION_FOR_USERS_OPT_OUT = :secret_scanning_push_protection_for_users_opt_out
    GENERIC_SECRETS_BLOCK = :secret_scanning_generic_secrets_block
    PERSIST_RESULTS_FOR_PUBLIC_REPOS = :secret_scanning_write_results_for_public_scans
    USER_SCOPED_ANCESTOR_SCAN = :secret_scanning_user_scoped_ancestor_scan
    LOWER_CONFIDENCE_PATTERNS_DARK_SHIP = :secret_scanning_lower_confidence_patterns_dark_ship
    GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS = :secret_scanning_generic_secrets_in_security_configurations
    CO_AUTHOR_ALERT_PERMISSIONS = :secret_scanning_co_author_alert_permissions
    OWNER_SERVICE_FLAGS_ON_ORG_ENABLEMENT = :secret_scanning_owner_service_flags_on_org_enablement
    GENERIC_SECRETS_FEEDBACK_LINK = :secret_scanning_generic_secrets_feedback_link
    SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS = :secret_scanning_show_single_alert_view_metadata_tags
    SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS = :secret_scanning_show_single_alert_view_related_alerts
    AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS = :ai_assisted_remediation_guidance_for_gh_pats
    DISPLAY_ALERT_PERMISSIONS = :secret_scanning_display_alert_permissions
    USE_DISPLAY_LOGIN_TWIRP = :secret_scanning_use_display_login_twirp
    AI_REMEDIATION_EXPERIMENTS = :secret_scanning_ai_remediation_experiments
    PLAID_UI_FILTERS = :secret_scanning_alert_plaid_ui_filters
    ASSESSMENT_RESCAN = :secret_risk_assessment_rescan
    DISABLE_RECOMMENDED_CONFIG = :secret_scanning_disable_recommended_config

    ASSESSMENTS_CHECK_ALL_REPOS_ENABLED = :secret_risk_assessment_all_repos_enabled
    DISPLAY_PREVIOUS_ASSESSMENTS = :secret_scanning_display_previous_assessments
    REVIEW_BYPASS_REQUESTS_ORG_FGR = :secret_scanning_review_bypass_requests_org_fgr
    DISMISSAL_REPO_FGR = :secret_scanning_dismissal_requests_repo_fgr
    REVIEW_BYPASS_REQUESTS_REPO_FGR = :secret_scanning_review_bypass_requests_repo_fgr
    VALIDITY_CHECKS = :secret_scanning_validity_checks
    DO_NOT_FILTER_EXPIRED_EXEMPTION_REQUESTS = :secret_scanning_do_not_filter_expired_exemption_requests
    SECRET_PROTECTION_PRICING_CALCULATOR = :security_assessments_enable_pricing_calculator
    SECRET_PROTECTION_PRICING_CALCULATOR_METERED_ORGS = :security_assessments_enable_pricing_calculator_for_metered_orgs
    SECRET_SCANNING_ALERT_ASSIGNEE = :secret_scanning_alert_assignee
    SECURITY_ASSESSMENTS_ENABLE_ROI_CALCULATOR = :security_assessments_enable_roi_calculator
    VALIDITY_CHECKS_ALLOWED_FOR_AWS_KEYS_WITHOUT_GROUPS = :secret_scanning_validity_checks_allowed_for_aws_keys_without_groups
    ENTERPRISE_DELEGATED_BYPASS = :secret_scanning_enterprise_delegated_bypass
    ENTERPRISE_DELEGATED_BYPASS_API = :secret_scanning_enterprise_bypass_requests_api
    OPENAI_PUSH_PROTECTION_PATCH = :ghsp_push_protection_openai_patch
  end

  # Indicates whether a given feature flag is enabled for the given target,
  # either directly or through its hierarchy ie. this method will return true
  # for a repository if the feature flag is enabled for the repo's org or business
  sig { params(target: T.any(Repository, Organization, Business, User), feature_flag: Symbol).returns(T::Boolean) }
  def self.feature_flag_enabled_in_hierarchy?(target, feature_flag)
    if target.is_a?(Repository)
      return ::FeatureFlag.vexi.enabled?(feature_flag, target, target.owner, target.owner&.business, default: false)
    end

    if target.is_a?(Business)
      return ::FeatureFlag.vexi.enabled?(feature_flag, target, default: false)
    end

    # For Organizations and Users
    ::FeatureFlag.vexi.enabled?(feature_flag, target, target.business, default: false)
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
