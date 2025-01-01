# typed: true
# frozen_string_literal: true

class Repos::CopilotSettings::SweAgentController < AbstractRepositoryController
  include GitHub::Memoizer
  include Variables::Helper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update_mcp_configuration, :update_firewall_configuration]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :dotcom_required
  before_action :parse_json_params, only: [:update_mcp_configuration, :update_firewall_configuration]
  before_action :has_access_to_swe_agent

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:index]

  def self.react_bundle_name
    "copilot-swe-agent-settings"
  end

  def index
    config = Copilot::SweAgentConfiguration.find_by(resource: current_repository)

    render_react_app(
      payload: {
        mcpConfiguration: config&.mcp_configuration,
        firewallConfiguration: firewall_ui_enabled? ? get_current_firewall_config : nil,
        endpoint: repo_repo_settings_copilot_swe_agent_path(current_repository.owner, current_repository.name),
        actionsVariablePath: repository_variables_path(user_id: current_repository.owner, repository: current_repository, app_name: Variables::AppsHelper::ACTIONS_APP_NAME),
        access_warning_banner_content: access_warning_banner_content,
      },
      title: Copilot::COPILOT_SWE_AGENT,
      page_data: {
        selected_link: :repo_settings_copilot_swe_agent
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  def firewall_allowlist_edit # rubocop:disable GitHub/UseRestfulActions
    render_404 unless firewall_ui_enabled?

    render_react_app(
      payload: {
        firewallConfiguration: firewall_ui_enabled? ? get_current_firewall_config : nil,
        endpoint: repo_repo_settings_copilot_swe_agent_path(owner.display_login, current_repository.name),
        actionsVariablePath: repository_variables_path(user_id: current_repository.owner, repository: current_repository, app_name: Variables::AppsHelper::ACTIONS_APP_NAME),
      },
      title: Copilot::COPILOT_SWE_AGENT,
      page_data: {
        selected_link: :repo_settings_copilot_swe_agent
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  def update_mcp_configuration # rubocop:disable GitHub/UseRestfulActions
    # Validate MCP configuration if present
    begin
      ::JSON::Validator.validate!(Repos::CopilotSettings::McpSchema::MCPPayload::EXPECTED_MCP_CONFIGURATION_SCHEMA, params["mcp_configuration"], json: true)
    rescue ::JSON::Schema::JsonParseError, ::JSON::Schema::ValidationError => e
      Rails.logger.error("Invalid MCP configuration JSON: #{e.message}, submitted parameters: #{params["mcp_configuration"]}")
      render json: { message: "Invalid MCP configuration JSON. \n #{e.message}" }, status: :unprocessable_entity and return
    end

    config = Copilot::SweAgentConfiguration.find_or_initialize_by(
      resource: current_repository
    )

    config.mcp_configuration = params["mcp_configuration"]

    config.updated_by = current_user

    if config.save
      render json: {
        message: "MCP configuration saved successfully",
        lastEdited: {
          login: current_user.display_login,
          updated_at: config.updated_at
        }
      }
      Copilot::Instrumenter.instrument_swe_agent_mcp_config_updated(
        repo: current_repository,
        actor: current_user,
        new_config: config.mcp_configuration,
      )
    else
      render json: { message: config.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  sig { returns(T.nilable(String)) }
  def access_warning_banner_content # rubocop:todo GitHub/UseRestfulActions
    public_user = Copilot::Public::User.new(current_user)

    if !public_user.has_copilot_access? || !public_user.has_required_sku_for_copilot_coding_agent?
      return "You can configure Copilot coding agent for other users with access to this repository, but you won't be able to assign tasks to Copilot because you don't have a Copilot Pro, Copilot Pro+, Copilot Business or Copilot Enterprise license."
    elsif !public_user.swe_agent_enabled?
      return "You can configure Copilot coding agent for other users with access to this repository, but you won't be able to assign tasks to Copilot because the Copilot coding agent policy has been disabled by an administrator."
    end

    nil
  end

  def update_firewall_configuration # rubocop:todo GitHub/UseRestfulActions
    return render json: { error: "Firewall UI is not enabled" }, status: :unprocessable_entity unless firewall_ui_enabled?

    is_valid, reason = validate_firewall_rules(params[:rules])
    return render json: { error: reason }, status: :unprocessable_entity unless is_valid

    if params[:enabled]
      set_actions_variable("COPILOT_AGENT_FIREWALL_ENABLED", "true")
    else
      set_actions_variable("COPILOT_AGENT_FIREWALL_ENABLED", "false")
    end

    if params[:useDefaultRules]
      delete_actions_variable("COPILOT_AGENT_FIREWALL_ALLOW_LIST")
      set_actions_variable("COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS", join_rules_or_blank(params[:rules]))
    else
      set_actions_variable("COPILOT_AGENT_FIREWALL_ALLOW_LIST", join_rules_or_blank(params[:rules]))
      delete_actions_variable("COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS")
    end

    render json: get_current_firewall_config
  rescue StandardError => e
    Failbot.report(e)
    render json: { error: "An unexpected error occurred" }, status: :internal_server_error
  end

  private

  def join_rules_or_blank(rules)
    # Variables don't support having no content. The intent of a customer with useDefaultRules: false
    # and an empty rule array is to block nearly everything. To achieve this, we set the allow list to an empty string.
    return " " if rules.blank?
    rules.join(",")
  end

  def firewall_ui_enabled?
    FeatureFlag.vexi.enabled?(:sweagentd_firewall_ui, current_user, default: false)
  end

  def has_access_to_swe_agent # rubocop:todo GitHub/UseRestfulActions
    render_404 unless current_repository.owner.copilot_swe_agent_enabled_for?(current_repository)
  end

  def variables_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_variables_app ||= Variables::AppsHelper.app_for(Variables::AppsHelper::ACTIONS_APP_NAME, current_user)
  end

  class FirewallConfiguration < T::Struct
    const :enabled, T::Boolean, default: true
    const :useDefaultRules, T::Boolean, default: true
    const :rules, T::Array[String], default: []
    const :error, T.nilable(String), default: nil
  end

  sig { params(name: String).void }
  def delete_actions_variable(name)
    begin
      # First try to fetch the existing variable
      result = Variables.fetch(
        name: name,
        app: variables_app,
        owner: current_repository,
        actor: current_user,
      )
    rescue Variables::Error
      # If the variable does not exist, result will be nil
      result = nil
    end

    if result != nil
      Variables.delete(name: name,
          app: variables_app,
          owner: current_repository,
          actor: current_user)
    end
  end

  sig { params(name: String, value: String).void }
  def set_actions_variable(name, value)
    begin
      # First try to fetch the existing variable
      result = Variables.fetch(
        name: name,
        app: variables_app,
        owner: current_repository,
        actor: current_user,
      )
    rescue Variables::Error
      # If the variable does not exist, result will be nil
      result = nil
    end

    # Validate the variable before saving
    validation = Varz.validate_variable(name, value)
    unless validation.succeeded?
      raise StandardError, "Variable validation failed: #{validation.error}"
    end

    encoded_value = Base64.strict_encode64(value)

    begin
      if result&.variable
        # Variable exists, update it
        Variables.update(
          name: name,
          app: variables_app,
          owner: current_repository,
          actor: current_user,
          value: encoded_value,
          updated_name: name,
        )
      else
        # Variable doesn't exist, create it
        Variables.store(
          name: name,
          app: variables_app,
          owner: current_repository,
          actor: current_user,
          value: encoded_value,
        )
      end
    rescue Variables::Error => e
      error_message = "Failed to save variable. Please try again."

      if e.status == 429
        error_message = "Failed to save variable, you've reached the variable limit."
      elsif e.status == 409
        error_message = "A repository variable with this name already exists."
      end

      raise StandardError, error_message
    end

  end

  sig { returns(FirewallConfiguration) }
  def get_current_firewall_config
    begin
      response = Variables.for_app_paginated(variables_app, owner: current_repository, actor: current_user, page: 1, per_page: 1000)
    rescue Variables::Error
      flash[:error] = "Failed to load internet access rules. To try again, please refresh the page."
      raise
    end

    return FirewallConfiguration.new(enabled: true, useDefaultRules: true, rules: []) if response.blank?

    variables = T.let(response[:variables].map do |variable|
      [
        variable.name,
        Base64.strict_decode64(variable.value)
      ]
    end.to_h, T::Hash[String, String])

    is_enabled = variables["COPILOT_AGENT_FIREWALL_ENABLED"]
    allow_list_additions = variables["COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS"]
    allow_list = variables["COPILOT_AGENT_FIREWALL_ALLOW_LIST"]
    is_valid, reason = validate_firewall_variable_configuration(is_enabled, allow_list_additions, allow_list)
    unless is_valid
      return FirewallConfiguration.new(error: reason)
    end

    enabled = variables["COPILOT_AGENT_FIREWALL_ENABLED"] || "true"

    use_default_rules = !variables.has_key?("COPILOT_AGENT_FIREWALL_ALLOW_LIST")
    if use_default_rules
      allowed_rules = variables["COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS"]&.split(",") || []
    else
      allowed_rules = variables["COPILOT_AGENT_FIREWALL_ALLOW_LIST"]&.split(",") || []
    end

    FirewallConfiguration.new(
      enabled: enabled == "true",
      useDefaultRules: use_default_rules,
      rules: allowed_rules.map(&:strip).reject(&:blank?)
    )
  end

  sig { params(is_enabled: T.nilable(String), allow_list_additions: T.nilable(String), allow_list: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
  def validate_firewall_variable_configuration(is_enabled, allow_list_additions, allow_list)
    if is_enabled&.present? && !(is_enabled == "true" || is_enabled == "false")
      return [false, "Invalid value for COPILOT_AGENT_FIREWALL_ENABLED. Only 'true' or 'false' are valid values."]
    end

    if allow_list_additions&.present? && allow_list&.present?
      return [false, "Both COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS and COPILOT_AGENT_FIREWALL_ALLOW_LIST are set. Either one or the other should be set, not both."]
    end

    rules_to_validate = allow_list_additions.present? ? allow_list_additions : allow_list
    if rules_to_validate.present?
      split_rules = rules_to_validate.split(",")
      rules_valid, reason = validate_firewall_rules(split_rules)
      return [rules_valid, reason] unless rules_valid
    end

    [true, nil]
  end

  sig { params(rules: T.nilable(T::Array[String])).returns([T::Boolean, T.nilable(String)]) }
  def validate_firewall_rules(rules)
    if rules.nil? || rules.empty?
      return [true, nil]
    end

    domain_pattern = /\A([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.([a-z]{2,63})\z|\A[a-z0-9][a-z0-9\-]{0,61}\z/

    rules.each do |rule|
      # Skip empty/whitespace items
      next if rule.strip.empty?

      # Check if it's an IP address
      if rule.count(".") == 3
        is_ip = rule.split(".").all? do |part|
          !part.empty? && part.chars.all? { |c| c >= "0" && c <= "9" }
        end
        next if is_ip
      end

      # Check if it's a URL
      if rule.include?("://")
        begin
          parsed_url = URI.parse(rule)

          if parsed_url.port && ![80, 443].include?(parsed_url.port)
            return [false, "Invalid rule defined. Only ports 80 and 443 are supported in URL rules. '#{rule}' uses port '#{parsed_url.port}'"]
          end

          if parsed_url.userinfo.present?
            return [false, "URLs with a username or password component are not allowed as could contain secrets"]
          end

          if parsed_url.query
            return [false, "URL has query parameters, not allowed as could contain secrets"]
          end

          next
        rescue URI::InvalidURIError
          return [false, "Failed to parse URL: #{rule}"]
        end
      end

      # Check if it's a valid domain
      unless domain_pattern.match?(rule.downcase)
        return [false, "Invalid rule '#{rule}'. Must be a valid domain, IP address, or URL"]
      end
    end

    [true, nil]
  end
end
