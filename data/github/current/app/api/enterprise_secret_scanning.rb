# typed: strict
# frozen_string_literal: true

class Api::EnterpriseSecretScanning < Api::Enterprise::App
  include Api::App::SecretScanningHelpers
  include Api::App::SecurityAnalysisSettingsHelpers
  include SecurityAnalysisSettingsHelper

  # business secret scanning alerts
  get "/enterprises/:enterprise_id/secret-scanning/alerts", operation_id: "secret-scanning/list-alerts-for-enterprise" do
    target = find_enterprise!

    validate_access target

    control_access :list_enterprise_secret_scanning_alerts,
      resource: target,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    # Filter by state, if provided in the query
    state = nil
    if params[:state]
      state = params[:state].downcase.to_sym
      if state != :open && state != :resolved
        deliver_error!(400, message: "State needs to be either 'open' or 'resolved'")
      end
    end

    # Filter by resolution, if provided in the query
    resolutions = []
    if params[:resolution]
      params[:resolution].split(",").each do |resolution|
        service_enum = get_service_enum_from_alert_resolution(resolution)
        if service_enum.nil?
          deliver_error!(422, message: "resolution is invalid: it must be one of 'revoked', 'false_positive', 'used_in_tests', 'pattern_deleted', 'pattern_edited' or 'wont_fix'")
        end
        resolutions << service_enum
      end
    end

    # Filter by validity, if provided in the query
    validity_service_params = get_service_enums_from_validity_param(params[:validity])
    unless validity_service_params[:error].nil?
      deliver_error!(422, message: validity_service_params[:error])
    end
    validities = validity_service_params[:validities]

    slug_types = nil
    if params[:secret_type]
      slug_types = params[:secret_type].split(",")
    end

    organization_ids = T.let([], T.untyped)
    GitHub.dogstats.distribution_time "secret_scanning.get_allowed_organization_ids.duration" do
      authorized_orgs, _ = authorized_and_unauthorized_organizations(target.id, cap_filter: cap_filter, fgp: :view_secret_scanning_alerts)
      organization_ids = authorized_orgs.pluck(:id)
    end

    results = get_alerts_for_orgs(
      target,
      organization_ids,
      state,
      slug_types,
      params[:sort],
      params[:direction],
      per_page,
      params[:before],
      params[:after],
      resolutions,
      Repository::VISIBILITIES,
      validities,
    )

    # If encrypted secrets were retrieved, we may be able to decrypt them here
    results[:alerts].each { |alert| set_raw_secret_from_encrypted_secret(alert) }

    alerts_without_raw_secrets = results[:alerts].select { |alert| alert.raw_secret.blank? }
    alerts_without_raw_secrets.each { |alert| SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert) }

    setup_cursor_paging_links(results)
    deliver :enterprise_secret_scanning_alerts_hash, { alerts: results[:alerts] }
  end

  # business security analysis settings
  get "/enterprises/:enterprise_id/code_security_and_analysis", operation_id: "secret-scanning/get-security-analysis-settings-for-enterprise" do
    enterprise = find_enterprise!

    control_access :read_enterprise_code_security_and_analysis_settings,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    deliver_raw code_security_and_analysis_response(enterprise), status: 200
  end

  patch "/enterprises/:enterprise_id/code_security_and_analysis", operation_id: "secret-scanning/patch-security-analysis-settings-for-enterprise" do
    enterprise = find_enterprise!

    control_access :update_enterprise_code_security_and_analysis_settings_new_repos,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    data = receive_with_openapi

    allowed_keys = %w[
      advanced_security_enabled_for_new_repositories
      dependabot_alerts_enabled_for_new_repositories
      secret_scanning_enabled_for_new_repositories
      secret_scanning_push_protection_enabled_for_new_repositories
      secret_scanning_push_protection_custom_link
    ]

    if SecretScanning::Features::Business::LowerConfidencePatterns.new(enterprise).enablement_api_available?
      allowed_keys.push("secret_scanning_non_provider_patterns_enabled_for_new_repositories")
    end
    unless SecretScanning::Features::Owner::ValidityChecks.new(enterprise).show_security_config_ux?
      allowed_keys.push("secret_scanning_validity_checks_enabled")
    end

    if AdvancedSecurity::Features::Business::AdvancedSecurity.new(enterprise).feature_available_for_user_repositories?
      allowed_keys.push("advanced_security_enabled_new_user_namespace_repos")
    end

    configurable_settings = data.select { |key, _| allowed_keys.include?(key) }

    if configurable_settings.fetch("secret_scanning_push_protection_custom_link", "").nil?
      # the custom link was explicitly set to null so we want to disable it
      configurable_settings["secret_scanning_push_protection_custom_link_enabled"] = false
    elsif configurable_settings.key?("secret_scanning_push_protection_custom_link")
      # enable custom link since it was passed in
      configurable_settings["secret_scanning_push_protection_custom_link_enabled"] = true
    end

    if BlockedSettings.new(enterprise).any?
      deliver_error!(422, errors: ["Security product toggling is in progress."])
    end

    error_message = update_tenant_security_and_analysis_configuration(
      enterprise,
      settings: configurable_settings,
      should_remove_custom_link_enablement_field: changeset_active?(:remove_secret_scanning_custom_link_enablement_field),
    )
    if error_message.present?
      GitHub.logger.info(
        "code.namespace" => "Api::EnterpriseSecretScanning",
        "code.function" => "update_tenant_security_and_analysis_configuration",
        "exception.message" => error_message,
        "gh.business.id" => enterprise.id,
        "gh.business.name" => enterprise.name,
      )
      deliver_error!(422, errors: [error_message])
    end

    deliver_empty status: 204
  end

  post "/enterprises/:enterprise_id/:security_feature/:enablement", operation_id: "secret-scanning/post-security-product-enablement-for-enterprise"  do
    enterprise = find_enterprise!

    control_access :update_enterprise_security_product_enablement,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    deliver_error!(422, errors: ["Security product toggling is in progress."]) if settings_blocked?(enterprise, security_feature: params[:security_feature])

    security_features = {
      "advanced_security" => :advanced_security,
      "dependabot_alerts" => :security_alerts,
      "secret_scanning" => :secret_scanning,
      "secret_scanning_push_protection" => :secret_scanning_push_protection
    }
    if SecretScanning::Features::Business::LowerConfidencePatterns.new(enterprise).enablement_api_available?
      security_features["secret_scanning_non_provider_patterns"] = :secret_scanning_lower_confidence_patterns
    end

    if AdvancedSecurity::Features::Business::AdvancedSecurity.new(enterprise).feature_available_for_user_repositories?
      security_features["advanced_security_user_namespace"] = :advanced_security_user_namespace
    end

    if security_features.keys.exclude?(params[:security_feature]) || %w[enable_all disable_all].exclude?(params[:enablement])
      deliver_error! 404
    end

    update_key = { security_features[params[:security_feature]] => params[:enablement] }
    error_message = UpdateSecuritySettings.perform(enterprise, update_key, actor: current_user, source: "rest-api").try(:fetch, :error, nil)
    if error_message.present?
      GitHub.logger.info(
        "code.namespace" => "Api::EnterpriseSecretScanning",
        "code.function" => "update_tenant_security_and_analysis_configuration",
        "exception.message" => error_message,
        "gh.business.id" => enterprise.id,
        "gh.business.name" => enterprise.name,
      )
      deliver_error!(422, errors: [error_message])
    end

    deliver_empty status: 204
  end

  private

  sig { params(enterprise: Business).returns(T::Hash[T.untyped, T.untyped]) }
  def code_security_and_analysis_response(enterprise)
    push_protection = SecretScanning::Features::Business::PushProtection.new(enterprise)
    token_scanning = SecretScanning::Features::Business::TokenScanning.new(enterprise)
    validity_checks = SecretScanning::Features::Business::ValidityChecks.new(enterprise)
    lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(enterprise)

    push_protection_custom_link = enterprise.get_push_protection_custom_message if push_protection.custom_message_active?
    res = {
      advanced_security_enabled_for_new_repositories: enterprise.advanced_security_enabled_on_new_repos?,
      dependabot_alerts_enabled_for_new_repositories: enterprise.security_alerts_enabled_for_new_repos?,
      secret_scanning_enabled_for_new_repositories: token_scanning.secret_scanning_enabled_for_new_repos?,
      secret_scanning_push_protection_enabled_for_new_repositories: push_protection.enabled_for_new_repos?,
      secret_scanning_push_protection_custom_link: push_protection_custom_link,
    }

    if lower_confidence_patterns.enablement_api_available?
      res["secret_scanning_non_provider_patterns_enabled_for_new_repositories"] = lower_confidence_patterns.enabled_for_new_repos?
    end

    if !GitHub.single_or_multi_tenant_enterprise? && !SecretScanning::Features::Owner::ValidityChecks.new(enterprise).show_security_config_ux?
      res["secret_scanning_validity_checks_enabled"] = validity_checks.enabled?
    end

    if AdvancedSecurity::Features::Business::AdvancedSecurity.new(enterprise).feature_available_for_user_repositories?
      res["advanced_security_enabled_for_new_user_namespace_repositories"] = enterprise.advanced_security_enabled_on_new_user_namespace_repos?
    end

    res
  end

  sig { params(business: Business).void }
  def validate_access(business)
    return if SecretScanning::Features::Business::TokenScanning.new(business).feature_available?

    deliver_error! 404
  end
end
