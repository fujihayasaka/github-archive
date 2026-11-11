# typed: strict
# frozen_string_literal: true

# TODO:
# - Fix false positive rubocops in authz tests
class Api::SecretScanning::PatternConfigurations < Api::App
  Errors = ::SecretScanning::Errors

  # List org pattern configs
  get "/organizations/:organization_id/secret-scanning/pattern-configurations", operation_id: "secret-scanning/list-org-pattern-configs" do
    org = T.let(find_org!, Organization)
    access_org!(org)
    control_access(
      :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )

    pattern_config, err = SecretScanning::Services::PatternConfigsService.get_pattern_config_by_owner(org, current_user)
    deliver_error!(500, message: "An error occurred. Please try again later.") if err || pattern_config.nil?
    deliver_raw(pattern_config.serialize_api(has_parent: org.business.present?))
  end

  # Update org pattern configs
  patch "/organizations/:organization_id/secret-scanning/pattern-configurations", operation_id: "secret-scanning/update-org-pattern-configs", read_from_replicas: false do
    org = T.let(find_org!, Organization)
    access_org!(org)
    control_access(:manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
    )
    update_pattern_config!(org)
  end

  # List enterprise pattern configs
  get "/enterprises/:enterprise_id/secret-scanning/pattern-configurations", operation_id: "secret-scanning/list-enterprise-pattern-configs" do
    enterprise = T.let(find_enterprise!, Business)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )

    pattern_config, err = SecretScanning::Services::PatternConfigsService.get_pattern_config_by_owner(enterprise, current_user)
    deliver_error!(500, message: "An error occurred. Please try again later.") if err || pattern_config.nil?
    deliver_raw(pattern_config.serialize_api(has_parent: false))
  end

  # Update enterprise pattern configs
  patch "/enterprises/:enterprise_id/secret-scanning/pattern-configurations", operation_id: "secret-scanning/update-enterprise-pattern-configs", read_from_replicas: false do
    enterprise = T.let(find_enterprise!, Business)
    access_biz!(enterprise)
    control_access(
      :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
    )
    update_pattern_config!(enterprise)
  end

  private

  sig { params(owner: T.any(Organization, Business)).void }
  def update_pattern_config!(owner)
    req = receive_with_openapi
    row_version = req["pattern_config_version"]
    provider_pattern_settings_params = req["provider_pattern_settings"] || []
    custom_pattern_settings_params = req["custom_pattern_settings"] || []

    if provider_pattern_settings_params.empty? && custom_pattern_settings_params.empty?
      deliver_error!(422, message: "Pattern settings required")
    end

    provider_pattern_settings = provider_pattern_settings_params.map do |setting|
      result, error = ::SecretScanning::Models::PatternConfigurations::PatternOverrideUpdate.from_params(setting)
      deliver_error!(422, message: "Failed to parse provider patterns: #{error}") if error
      deliver_error!(500, message: "Failed to parse provider patterns: unknown error occurred") if result.nil?
      result
    end

    custom_pattern_settings = custom_pattern_settings_params.map do |setting|
      result, error = ::SecretScanning::Models::PatternConfigurations::CustomPatternOverrideUpdate.from_params_api(setting)
      deliver_error!(422, message: "Failed to parse custom patterns: #{error}") if error
      deliver_error!(500, message: "Failed to parse custom patterns: unknown error occurred") if result.nil?
      result
    end

    row_version_out, number_out, err = SecretScanning::Services::PatternConfigsService.upsert_pattern_config(
      owner:,
      user: current_user,
      row_version:,
      provider_pattern_settings:,
      custom_pattern_settings:,
    )
    deliver_error!(409, message: "One of your pattern_config or custom_pattern versions does not match the server version. Re-fetch the entity to get the latest version data.") \
      if err.is_a?(Errors::RowVersionMismatch)
    deliver_error!(422, message: err.message) if err.is_a?(Errors::ServiceInvalidArgument)
    deliver_error!(500, message: "An error occurred. Please try again later.") if err || row_version_out.nil? || number_out.nil?
    deliver_raw({ pattern_config_version: row_version_out })
  end

  sig { params(org: Organization).void }
  def access_org!(org)
    deliver_error!(404, message: "Feature not available in this organization.") unless SecretScanning::Features::Org::PushProtection.new(org).pattern_configs_available?
  end

  sig { params(biz: Business).void }
  def access_biz!(biz)
    deliver_error!(404, message: "Feature not available in this enterprise.") unless biz.seats_plan_full?
    deliver_error!(404, message: "Feature not available in this enterprise.") unless SecretScanning::Features::Business::TokenScanning.new(biz).feature_available?
  end
end
