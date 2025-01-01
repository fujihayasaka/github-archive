# typed: true
# frozen_string_literal: true

class Api::EnterpriseCodeSecurityConfigurations < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::CodeSecurityConfigurationsHelper

  DELEGATED_BYPASS_OPTIONS_LABEL = "secret_scanning_delegated_bypass_options"
  FORBIDDEN_MESSAGE = "You are not authorized to perform this operation."
  SUPPORTED_STATUS_FILTERS = RepositorySecurityConfiguration.states.keys.freeze

  # Get default code security configurations for an enterprise
  get "/enterprises/:enterprise_id/code-security/configurations/defaults", operation_id: "code-security/get-default-configurations-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :read_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    defaults = find_default_configurations!(enterprise)

    configurations = defaults.map do |default|
      SecurityConfiguration.find(default.security_configuration_id)
    end

    deliver(:default_code_security_configurations_hash, { defaults:, configurations:, target: enterprise, actor: current_user })
  end

  # Get code security configurations for an enterprise
  get "/enterprises/:enterprise_id/code-security/configurations", operation_id: "code-security/get-configurations-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :read_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configurations = SecurityConfiguration.where(target: enterprise).or(SecurityConfiguration.where(target_type: "global", target_id: 0)).order(:id)
    results = paginate_results(configurations)

    deliver(:code_security_configurations_hash, { configurations: results, target: enterprise })
  end

  # Gets a code security configuration available in an enterprise.
  get "/enterprises/:enterprise_id/code-security/configurations/:configuration_id", operation_id: "code-security/get-single-configuration-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :read_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configuration = find_configuration!(enterprise)

    deliver(:code_security_configuration_hash, { configuration:, target: enterprise })
  end

  # Creates a code security configuration for an enterprise
  post "/enterprises/:enterprise_id/code-security/configurations", operation_id: "code-security/create-configuration-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi
    validate_parameters!(data)

    begin
      configuration = SecurityConfiguration.new(target: enterprise).tap do |config|
        config.name = data["name"]
        config.description = data["description"]

        params_to_enablement(data).each do |feature, value|
          unless feature == DELEGATED_BYPASS_OPTIONS_LABEL
            config[feature] = value
          end
        end
      end
    rescue CodeSecurityConfigurationsHelper::MalformedParameterError => e
      deliver_error!(400, message: e.message)
    end

    if configuration.valid? && configuration.save
      # Skip creating policy record if enforcement is set to `unenforced`
      unless data["enforcement"] == "unenforced"
        # Default to `enforced` if enforcement is not provided
        enforcement = data["enforcement"].nil? ? :enforced : parse_enforcement(data["enforcement"])
        SecurityConfigurationPolicy.create_or_update(security_configuration_id: configuration.id, target: enterprise, enforcement:)
      end

      deliver(:code_security_configuration_hash, { configuration:, target: enterprise }, status: 201)
    else
      deliver_error!(422, message: human_readable_error_message(configuration.errors.messages))
    end
  end

  # Update a custom code security configuration for an enterprise.
  patch "/enterprises/:enterprise_id/code-security/configurations/:configuration_id", operation_id: "code-security/update-enterprise-configuration" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configuration = find_configuration!(enterprise)

    if configuration.is_github_recommended_configuration?
      deliver_error!(400, message: "Global configurations are not allowed to be updated.")
    end

    if enterprise.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Updating this configuration is not available until it's finished.")
    end

    data = receive_with_openapi
    validate_parameters!(data)

    if configuration
      configuration.name = data["name"] if data["name"]
      configuration.description = data["description"] if data["description"]
      configuration.enable_ghas = data["advanced_security"] == "enabled" if data["advanced_security"]

      PARAMETER_VALUES_TO_RECORD_ENABLEMENT_ATTRIBUTES.each do |feature, attribute|
        configuration[attribute] = data[feature] if data[feature]
      end

      PARAMETER_VALUES_TO_RECORD_OPTIONS_ATTRIBUTES.each do |options, attribute|
        configuration[attribute] = data[options] if data[options]
      end
    end

    if configuration.valid? && configuration.save
      policy = update_configuration_policy!(enterprise, configuration, data)

      if configuration.any_feature_previously_changed? || policy&.enforcement_previously_changed?
        options = configuration.any_feature_previously_changed? && configuration.secret_scanning_is_enabled? ? { publish_backfill_group_request: true } : {}

        SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
          security_configuration_id: configuration.id,
          enterprise_id: enterprise.id,
          actor_id: current_user.id,
          action: :update,
          options:
        )
      end

      deliver(:code_security_configuration_hash, { configuration:, target: enterprise })
    else
      deliver_error!(422, message: human_readable_error_message(configuration.errors.messages))
    end
  end

  # Delete a specific code security configuration by ID
  delete "/enterprises/:enterprise_id/code-security/configurations/:configuration_id", operation_id: "code-security/delete-configuration-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    if enterprise.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Deleting this configuration is not available until it's finished.")
    end

    configuration = find_configuration!(enterprise)

    if configuration.is_github_recommended_configuration?
      deliver_error!(400, message: "Global configurations are not allowed to be deleted.")
    end

    begin
      configuration.destroy!
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404, "Configuration not found"
    end

    deliver_empty status: 204
  end

  # Get repositories associated with an enterprise code security configuration
  get "/enterprises/:enterprise_id/code-security/configurations/:configuration_id/repositories", operation_id: "code-security/get-repositories-for-enterprise-configuration" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :read_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configuration = find_configuration!(enterprise)
    orgs = enterprise.organizations

    arel = configuration
      .repository_security_configurations
      .where(organization_id: orgs.pluck(:id))
      .order(:repository_id)
      .preload(:repository)

    if params[:status].presence
      # Split multiple statuses by comma, remove any whitespace, and downcase:
      statuses = params[:status].split(",").map! { _1.strip.downcase }

      # 'detached' is no longer a valid status, it is in a deprecation period
      # and should not be included as a valid status for this endpoint:
      if statuses.include?("detached")
        deliver_error!(400, message: "Unsupported status 'detached' passed")
      end

      # If the statuses queried include "all" then don't add additional filtering:
      unless statuses.include?("all")
        # If any unsupported statuses are passed
        statuses.each do |status|
          unless status.in?(SUPPORTED_STATUS_FILTERS)
            deliver_error!(400, message: "Unsupported status '#{status}' passed")
          end
        end

        arel = arel.where(state: statuses)
      end
    end

    repository_configurations = paginate_results(arel)
    deliver(:code_security_configuration_repository, repository_configurations)
  end

  # Set a default configuration for an enterprise
  put "/enterprises/:enterprise_id/code-security/configurations/:configuration_id/defaults", operation_id: "code-security/set-configuration-as-default-for-enterprise" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi
    configuration = find_configuration!(enterprise)

    if GitHub.multi_tenant_enterprise? && data["default_for_new_repos"] == "public"
      deliver_error!(422, message: "Public repository defaults are not supported in multi-tenant enterprise environments.")
    end

    case data["default_for_new_repos"]
    when "all" then
      default_for_new_public_repos = default_for_new_private_repos = true
    when "none"
      default_for_new_public_repos = default_for_new_private_repos = false
    when "private_and_internal"
      default_for_new_public_repos = false
      default_for_new_private_repos = true
    when "public"
      default_for_new_public_repos = true
      default_for_new_private_repos = false
    else
      # Default to false. We shouldn't reach this case because of OpenAPI validation, but Sorbet wants a non-nilable:
      default_for_new_public_repos = default_for_new_private_repos = false
    end

    SecurityConfigurationDefault.create_or_update_defaults(
      target: enterprise,
      security_configuration: T.must(configuration),
      default_for_new_public_repos:,
      default_for_new_private_repos:,
    )

    deliver(:code_security_configuration_default, {
      configuration:,
      default_for_new_repos: data["default_for_new_repos"],
      target: enterprise,
    })
  end

  # Attach an enterprise configuration to repositories
  post "/enterprises/:enterprise_id/code-security/configurations/:configuration_id/attach", operation_id: "code-security/attach-enterprise-configuration" do
    enterprise = find_enterprise!
    check_enterprise_security_config_ff!(enterprise)

    control_access :manage_enterprise_security_product_configurations,
      resource: enterprise,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi
    validate_attach_configuration!(enterprise, data)

    configuration = find_configuration!(enterprise)

    SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
      security_configuration_id: configuration.id,
      enterprise_id: enterprise.id,
      actor_id: current_user.id,
      action: :apply,
      override_existing_config: data["scope"] == "all",
      options: {}
    )

    deliver_empty status: 202
  end
end
