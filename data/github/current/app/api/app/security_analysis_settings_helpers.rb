# typed: true
# frozen_string_literal: true

module Api::App::SecurityAnalysisSettingsHelpers
  extend T::Sig
  include SecurityAnalysisSettingsHelper
  include Api::App::HelpersDependency

  BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP = {
    "advanced_security_enabled_for_new_repositories" => :advanced_security_enabled_new_repos,
    "advanced_security_enabled_new_user_namespace_repos" => :advanced_security_enabled_new_user_namespace_repos,
    "dependabot_alerts_enabled_for_new_repositories" => :security_alerts_new_repos,
    "dependabot_security_updates_enabled_for_new_repositories" => :vulnerability_updates_new_repos,
    "dependency_graph_enabled_for_new_repositories" => :dependency_graph_new_repos,
    "code_scanning_recommend_extended_query_suite" => :code_scanning_recommend_extended_query_suite,
    "secret_scanning_enabled_for_new_repositories" => :secret_scanning_new_repos,
    "secret_scanning_push_protection_enabled_for_new_repositories" => :secret_scanning_push_protection_new_repos,
    "secret_scanning_push_protection_custom_link_enabled" => :push_protection_custom_message_status,
    "secret_scanning_validity_checks_enabled" => :secret_scanning_validity_checks,
    "secret_scanning_non_provider_patterns" => :secret_scanning_lower_confidence_patterns,
    "secret_scanning_non_provider_patterns_enabled_for_new_repositories" => :secret_scanning_lower_confidence_patterns_new_repos,
  }.with_indifferent_access

  NON_BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP = {
    "secret_scanning_push_protection_custom_link" => :push_protection_custom_message
  }.with_indifferent_access

  COMBINED_SECURITY_AND_ANALYSIS_MAPS = BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP.merge(NON_BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP)

  SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_BLOCKED_SETTINGS_METHODS_MAP = {
    "advanced_security" => :advanced_security?,
    "code_scanning" => :code_scanning?,
    "secret_scanning" => :secret_scanning?,
    "secret_scanning_push_protection" => :push_protection?
  }.with_indifferent_access

  def security_and_analysis_only_access?(data)
    return false if data.keys.empty?

    security_and_analysis_settings = COMBINED_SECURITY_AND_ANALYSIS_MAPS.keys.to_set
    data.keys.all? { |k| security_and_analysis_settings.include?(k) }
  end

  sig do
    params(
      tenant: T.any(Business, Organization),
      should_remove_custom_link_enablement_field: T::Boolean,
      settings: T::Hash[String, T.untyped]
    ).returns(T.nilable(String))
  end
  def update_tenant_security_and_analysis_configuration(tenant, should_remove_custom_link_enablement_field:, settings: {})
    security_settings_params = settings
      .each_with_object({}) do |(key, value), hsh|
        internal_name = BOOLEAN_SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_INTERNAL_NAMES_MAP[key]
        next unless internal_name
        hsh[internal_name] = parse_bool(value) ? "enabled" : "disabled"
      end
      .with_indifferent_access

    if should_remove_custom_link_enablement_field
      if settings.has_key?("secret_scanning_push_protection_custom_link")
        if settings["secret_scanning_push_protection_custom_link"].present?
          security_settings_params[:push_protection_custom_message_status] = "enabled"
          security_settings_params[:push_protection_custom_message] = settings["secret_scanning_push_protection_custom_link"]
        else
          security_settings_params[:push_protection_custom_message_status] = "disabled"
        end
      else
        security_settings_params.delete(:push_protection_custom_message_status)
      end
    elsif security_settings_params[:push_protection_custom_message_status] == "enabled"
      security_settings_params[:push_protection_custom_message] = settings["secret_scanning_push_protection_custom_link"]
    end

    return nil if security_settings_params.blank?

    UpdateSecuritySettings.perform(tenant, security_settings_params, actor: current_user, source: "rest-api").try(:fetch, :error, nil)
  end

  sig do
    params(
      owner: T.any(Business, Organization),
      security_feature: T.nilable(String),
    ).returns(T::Boolean)
  end
  def settings_blocked?(owner, security_feature: nil)
    blocked_settings = BlockedSettings.new(owner)
    SECURITY_AND_ANALYSIS_SETTINGS_PUBLIC_TO_BLOCKED_SETTINGS_METHODS_MAP.each do |public_setting, blocked_settings_method|
      if security_feature == public_setting && blocked_settings.send(blocked_settings_method)
        return true
      end
    end
    false
  end
end
