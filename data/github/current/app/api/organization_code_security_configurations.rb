# typed: true
# frozen_string_literal: true

class Api::OrganizationCodeSecurityConfigurations < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::CodeSecurityConfigurationsHelper

  DELEGATED_BYPASS_OPTIONS_LABEL = "secret_scanning_delegated_bypass_options"
  FORBIDDEN_MESSAGE = "You are not authorized to perform this operation."
  SUPPORTED_STATUS_FILTERS = RepositorySecurityConfiguration.states.keys.freeze

  #########################################################################################################
  # Caution:
  # We allow users to interact with enterprise code security configurations at the organization level, but we
  # _must not_ allow them to modify enterprise code security configurations as the user may not be authorized to do so.
  #
  # Example: The user is a organization admin, but not an enterprise admin.
  # Reference: https://github.com/github/security-products-enablement/issues/1562
  #########################################################################################################

  get "/organizations/:organization_id/code-security/configurations/defaults", operation_id: "code-security/get-default-configurations" do
    org = find_org!

    control_access :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    defaults = find_default_configurations!(org)

    # Filter out enterprise/business configuration if it has the same default values as the organization configuration
    defaults = defaults.reject do |config|
      next unless config.target_type == "Business"

      defaults.any? do |org_config|
        org_config.target_type == "User" &&
          org_config.default_for_new_public_repos == config.default_for_new_public_repos &&
          org_config.default_for_new_private_repos == config.default_for_new_private_repos
      end
    end

    configurations = defaults.map do |default|
      SecurityConfiguration.find(default.security_configuration_id)
    end

    deliver(:default_code_security_configurations_hash, { defaults:, configurations:, target: org, actor: current_user })
  end

  # Get a specific code security configuration by ID
  get "/organizations/:organization_id/code-security/configurations/:configuration_id", operation_id: "code-security/get-configuration" do
    org = find_org!

    control_access :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configuration = find_configuration!(org)

    deliver(:code_security_configuration_hash, { configuration:, target: org, actor: current_user })
  end

  # Get all code security configurations for an organization
  get "/organizations/:organization_id/code-security/configurations", operation_id: "code-security/get-configurations-for-org" do
    org = find_org!

    control_access :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    target_type = params[:target_type] if params[:target_type].present?

    if target_type == "global"
      configurations = SecurityConfiguration.where(target_type: "global", target_id: 0).order(:id)
    else
      configurations = SecurityConfiguration \
        .where(target: [org, org.business].compact)
        .or(SecurityConfiguration.where(target_type: "global", target_id: 0))

      configurations = configurations.order(:id)
    end

    results = paginate_results(configurations)

    deliver(:code_security_configurations_hash, { configurations: results, target: org, actor: current_user })
  end

  # Get repositories associated with a code security configuration
  get "/organizations/:organization_id/code-security/configurations/:configuration_id/repositories", operation_id: "code-security/get-repositories-for-configuration" do
    org = find_org!

    control_access :read_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    configuration = find_configuration!(org)

    arel = configuration
      .repository_security_configurations
      .where(organization_id: org.id)
      .order(:repository_id)
      .preload(:repository)

    if params[:status].presence
      # Split multiple statuses by comma, remove any whitespace, and downcase:
      statuses = params[:status].split(",").map! { _1.strip.downcase }

      # Validate if both 'removed' and 'detached' are included:
      if statuses.include?("removed") && statuses.include?("detached")
        deliver_error!(422, message: "Both 'removed' and 'detached' cannot be used together, 'removed' is replacing 'detached'.")
      end

      # Map 'detached' to 'removed' to handle the deprecation period:
      statuses.map! { |status| status == "detached" ? "removed" : status }

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

    # Modify 'removed' back to 'detached' in the response if 'detached' was passed as status:
    repository_configurations.each do |repo_config|
      if params[:status].to_s.downcase.include?("detached") && repo_config.removed?
        repo_config.state = :detached
      end
    end

    deliver(:code_security_configuration_repository, repository_configurations)
  end

  post "/organizations/:organization_id/code-security/configurations", operation_id: "code-security/create-configuration" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi
    validate_parameters!(data)
    validate_secret_scanning_delegated_bypass!(org, data)

    ghas_bundled = org.advanced_security_license.billable_entity.advanced_security_products_bundled?

    begin
      klass = ghas_bundled ? SecurityConfiguration : UnbundledSecurityConfiguration
      configuration = klass.new(target: org).tap do |config|
        config.name = data["name"]
        config.description = data["description"]

        params_to_enablement(data, target: org, ghas_bundled:).each do |feature, value|
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
        enforcement = data["enforcement"].nil? ? SecurityConfigurationPolicy::Enforcement::Enforced : parse_enforcement(data["enforcement"])
        SecurityConfigurationPolicy.create_or_update(security_configuration_id: configuration.id, target: org, enforcement:,)
      end

      if configuration.secret_scanning_delegated_bypass_enabled?
        reviewers = data.dig(DELEGATED_BYPASS_OPTIONS_LABEL, "reviewers")
        if reviewers && reviewers.any?
          reviewers.each do |reviewer|
            reviewer["security_configuration_id"] = configuration.id
            reviewer["owner_scope"] = "ORGANIZATION_SCOPE"
            reviewer["owner_id"] = org.id
          end
          SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(org, configuration.id, reviewers, current_user)
        end
      end

      deliver(:code_security_configuration_hash, { configuration:, target: org, actor: current_user }, status: 201)
    else
      deliver_error!(422, message: human_readable_error_message(configuration.errors.messages))
    end
  end

  patch "/organizations/:organization_id/code-security/configurations/:configuration_id", operation_id: "code-security/update-configuration" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    if org.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Updating this configuration is not available until it's finished.")
    end

    configuration = find_configuration!(org)

    if configuration.is_github_recommended_configuration?
      deliver_error!(400, message: "Global configurations are not allowed to be updated.")
    end

    data = receive_with_openapi
    validate_parameters!(data)
    validate_secret_scanning_delegated_bypass!(org, data)

    if configuration
      configuration.name = data["name"] if data["name"]
      configuration.description = data["description"] if data["description"]
      set_sku_attributes!(configuration:, data:)

      PARAMETER_VALUES_TO_RECORD_ENABLEMENT_ATTRIBUTES.each do |feature, attribute|
        configuration[attribute] = data[feature] if data[feature]
      end

      PARAMETER_VALUES_TO_RECORD_OPTIONS_ATTRIBUTES.each do |options, attribute|
        unless options == DELEGATED_BYPASS_OPTIONS_LABEL
          configuration[attribute] = data[options] if data[options]
        end
      end
    end

    if !configuration.organization? && configuration.changes.any?
      GitHub.logger.info(
        "elcs_used_on_org_endpoint",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.security_configuration.id" => configuration.id,
      )
      deliver_error!(400, message: "This endpoint can only be used to update the organizational enforcement of an enterprise code security configuration.")
    end

    if configuration.valid? && configuration.save
      policy = update_configuration_policy!(org, configuration, data)

      if configuration.secret_scanning_delegated_bypass_is_disabled_or_not_set?
        SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(org, configuration.id, current_user)
      else
        if configuration.secret_scanning_delegated_bypass_enabled?
          reviewers = data.dig(DELEGATED_BYPASS_OPTIONS_LABEL, "reviewers")
          if reviewers && reviewers.any?
            reviewers.each do |reviewer|
              reviewer["security_configuration_id"] = configuration.id
              reviewer["owner_scope"] = "ORGANIZATION_SCOPE"
              reviewer["owner_id"] = org.id
            end
            SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(org, configuration.id, reviewers, current_user)
          end
        end
      end

      if configuration.any_feature_previously_changed? || policy&.enforcement_previously_changed?
        options = configuration.any_feature_previously_changed? && configuration.secret_scanning_scan_triggering_feature_is_enabled? ? { publish_backfill_group_request: true } : {}
        SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id: configuration.id,
          organization_id: org.id,
          actor_id: current_user.id,
          action: :update,
          repository_ids: nil,
          options:
        )
      end

      deliver(:code_security_configuration_hash, { configuration:, target: org, actor: current_user })
    else
      deliver_error!(422, message: human_readable_error_message(configuration.errors.messages))
    end
  end

  # Detach repository(s) from code security configurations
  delete "/organizations/:organization_id/code-security/configurations/detach", operation_id: "code-security/detach-configuration" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi

    if org.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Detaching repositories is not available until it's finished.")
    end

    repository_ids = data["selected_repository_ids"]

    GitHub.dogstats.count(
        "security_products_enablement.api.detach_configuration_repository_count",
        repository_ids.count,
      )

    GitHub.logger.info(
      "detach configuration repository count",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.security_configuration.repository_count" => repository_ids.count,
      "gh.actor.id" => current_user.id,
      "gh.organization.id" => org.id,
    )

    repository_security_configurations = RepositorySecurityConfiguration.
      preload(:user, :repository, :security_configuration).
      where(
        organization_id: org.id,
        repository_id: repository_ids
      )

    repository_security_configurations.each do |repository_security_configuration|
      repository_security_configuration.destroy!
    end

    deliver_empty status: 204
  end

  # Delete a specific code security configuration by ID
  delete "/organizations/:organization_id/code-security/configurations/:configuration_id", operation_id: "code-security/delete-configuration" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    if org.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Deleting this configuration is not available until it's finished.")
    end

    configuration = find_configuration!(org)

    if configuration.is_github_recommended_configuration?
      deliver_error!(400, message: "Global configurations are not allowed to be deleted.")
    end

    unless configuration.organization?
      GitHub.logger.info(
        "elcs_used_on_org_endpoint",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.security_configuration.id" => configuration.id,
      )
      deliver_error!(400, message: "Only organization code security configurations can use this endpoint.")
    end

    begin
      if configuration.secret_scanning_delegated_bypass_enabled?
        SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(org, configuration.id, current_user)
      end
      configuration.destroy!
    rescue ActiveRecord::RecordNotFound
      return deliver_error 404, "Configuration not found"
    end

    deliver_empty status: 204
  end

  put "/organizations/:organization_id/code-security/configurations/:configuration_id/defaults", operation_id: "code-security/set-configuration-as-default" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi
    configuration = find_configuration!(org)

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
      target: org,
      security_configuration: configuration,
      default_for_new_public_repos:,
      default_for_new_private_repos:,
    )

    deliver(:code_security_configuration_default, {
      configuration:,
      default_for_new_repos: data["default_for_new_repos"],
      target: org,
    })
  end

  post "/organizations/:organization_id/code-security/configurations/:configuration_id/attach", operation_id: "code-security/attach-configuration" do
    org = find_org!

    control_access :manage_org_security_product_configurations,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE

    data = receive_with_openapi

    validate_attach_configuration!(org, data)

    configuration = find_configuration!(org)

    scope = data["scope"]
    SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
      security_configuration_id: configuration.id,
      organization_id: org.id,
      actor_id: current_user.id,
      action: :apply,
      repository_ids: scope == "selected" ? data["selected_repository_ids"] : nil,
      repository_query: scope == "selected" ? nil : repository_query(scope),
      override_existing_config: true,
      options: {}
    )

    deliver_empty status: 202
  end
end
