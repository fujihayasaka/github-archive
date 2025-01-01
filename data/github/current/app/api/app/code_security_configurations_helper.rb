# typed: true
# frozen_string_literal: true

module Api::App::CodeSecurityConfigurationsHelper
  extend T::Helpers

  include GitHub::Memoizer

  DEFAULT_PER_PAGE = 30
  MAXIMUM_PER_PAGE = 100

  MalformedParameterError = Class.new(StandardError)

  # This map handles all parameters which use an enabled/disabled/not-set enum value
  PARAMETER_VALUES_TO_RECORD_ENABLEMENT_ATTRIBUTES = {
    "code_scanning_default_setup" => "code_scanning",
    "dependency_graph_autosubmit_action" => "dependency_graph_autosubmit_action",
    "dependabot_alerts" => "dependabot_alerts",
    "dependabot_security_updates" => "dependabot_security_updates",
    "dependency_graph" => "dependency_graph",
    "private_vulnerability_reporting" => "private_vulnerability_reporting",
    "secret_scanning" => "secret_scanning",
    "secret_scanning_non_provider_patterns" => "secret_scanning_non_provider_patterns",
    "secret_scanning_push_protection" => "secret_scanning_push_protection",
    "secret_scanning_delegated_bypass" => "secret_scanning_delegated_bypass",
    "secret_scanning_validity_checks" => "secret_scanning_validity_checks",
  }.freeze

  # This map handles all parameters which are filtered through feature options.
  PARAMETER_VALUES_TO_RECORD_OPTIONS_ATTRIBUTES = {
    "dependency_graph_autosubmit_action_options" => "dependency_graph_autosubmit_action_options",
    "secret_scanning_delegated_bypass_options" => "secret_scanning_delegated_bypass_options",
    "code_scanning_default_setup_options" => "code_scanning_options",
  }

  requires_ancestor { Api::App }

  sig { params(target: T.any(Organization, Business)).returns(SecurityConfiguration) }
  def find_configuration!(target)
    id = int_id_param! key: :configuration_id, halt: true
    configuration = SecurityConfiguration \
      .where(id:, target:)
      .or(SecurityConfiguration.where(id:, target_type: "global", target_id: 0))
      .first

    # If configuration is not found, we should check if an enterprise level configuration exists for the given id
    if configuration.blank? && target.is_a?(Organization) && target.business.present?
      configuration = SecurityConfiguration.where(id:, target: target.business).first
    end

    deliver_error!(404, message: "No code security configuration found for id #{id}") unless configuration

    configuration
  end

  sig { params(target: T.any(Organization, Business)).returns(T::Array[SecurityConfigurationDefault]) }
  def find_default_configurations!(target)
    SecurityConfigurationDefault.find_for(target:, visibility: :all)
  end

  sig { params(target: T.any(Organization, Business), configuration: SecurityConfiguration, data: Hash).returns(T.nilable(SecurityConfigurationPolicy)) }
  def update_configuration_policy!(target, configuration, data)
    return if data["enforcement"].nil?

    new_enforcement = parse_enforcement(data["enforcement"])

    SecurityConfigurationPolicy.create_or_update(security_configuration_id: configuration.id, target:, enforcement: new_enforcement)
  end

  sig { params(enforcement: String).returns(Symbol) }
  def parse_enforcement(enforcement)
    enforcement == "enforced" ? :enforced : :not_enforced
  end

  sig { params(data: Hash).returns(Hash) }
  def params_to_enablement(data)
    manager = SecurityProductsEnablement::SecurityProductsManager.new
    output = {}

    PARAMETER_VALUES_TO_RECORD_ENABLEMENT_ATTRIBUTES.each do |feature, attribute|
      # Enable Dependency graph by default if not provided and it's installed
      if manager.dependency_graph_enabled? && feature == "dependency_graph" && data[feature].nil?
        output[attribute] = "enabled"
        next
      end

      enablement = case data[feature]
      when "enabled" then "enabled"
      when "disabed" then "disabled"
      when "not_set" then "not_set"
      else "disabled" # If the param is missing, default to disabling the feature.
      end

      output[attribute] = enablement
    end

    PARAMETER_VALUES_TO_RECORD_OPTIONS_ATTRIBUTES.each do |feature, opts|
      output[opts] = data[feature]
    end

    if SecurityConfiguration::GHAS_FEATURES.any? { |f| output[f.to_s] == "enabled" } && data["advanced_security"] != "enabled"
      # If any GHAS features were set to enabled and GHAS is not enabled we want to warn the user:
      raise MalformedParameterError.new("GitHub advanced security must be enabled when any GHAS feature is set to enabled")
    elsif data["advanced_security"] == "enabled"
      # If not, set enable_ghas only if advanced_security param was set to enabled:
      output["enable_ghas"] = true
    else
      # Default to false:
      output["enable_ghas"] = false
    end

    output
  end

  sig { params(relation: ActiveRecord::Relation).returns(T::untyped) }
  def paginate_results(relation)
    per_page = (params[:per_page].present? ? int_id_param!(key: :per_page, halt: true) : DEFAULT_PER_PAGE)
      .clamp(1, MAXIMUM_PER_PAGE)

    before = params[:before].presence
    after = params[:after].presence
    first, last = before ? [nil, per_page] : [per_page, nil]

    platform_relation = Platform::ConnectionWrappers::Relation.new(
      relation,
      before:,
      after:,
      first:,
      last:,
    )

    set_cursor_based_pagination_headers(
      page_info: platform_relation.page_info,
      has_next_page: platform_relation.has_next_page,
      has_previous_page: platform_relation.has_previous_page,
    )

    platform_relation.edge_nodes.sync
  end

  sig { params(page_info: Platform::ConnectionWrappers::PageInfo, has_next_page: T::Boolean, has_previous_page: T::Boolean).void }
  def set_cursor_based_pagination_headers(page_info:, has_next_page:, has_previous_page:)
    if has_next_page
      @links.add_current({ after: page_info.end_cursor, before: nil, page: nil }, rel: "next")
    end

    if has_previous_page
      @links.add_current({ before: page_info.start_cursor, after: nil, page: nil }, rel: "prev")
    end
  end

  sig { params(error_messages: T::Hash[Symbol, T::Array[String]]).returns(String) }
  def human_readable_error_message(error_messages)
    messages = []
    if error_messages[:name].present?
      messages << "Name " + T.must(error_messages[:name]&.first)
    end

    if error_messages[:enable_ghas].present?
      messages << "GitHub advanced security must be enabled when any GHAS feature is set to enabled"
    end

    if error_messages[:dependency_graph_autosubmit_action].present?
      messages << "Dependency graph must be enabled when Automatic dependency submission is enabled"
    end

    if error_messages[:dependency_graph_autosubmit_action_options].present?
      messages << "Automatic dependency submission options can only be set if the feature is enabled"
    end

    if error_messages[:code_scanning_options].present?
      messages << "Code scanning options can only be set if the feature is enabled"
    end

    if error_messages[:dependabot_alerts].present?
      messages << "Dependency graph must be enabled when Dependabot alerts is enabled"
    end

    if error_messages[:dependabot_security_updates].present?
      messages << "Dependabot alerts must be enabled when Dependabot security updates is enabled"
    end

    if error_messages[:secret_scanning_push_protection].present?
      messages << "Secret scanning must be enabled when secret scanning push protection is enabled"
    end

    if error_messages[:secret_scanning_delegated_bypass].present?
      messages << "Push protection must be enabled when secret scanning delegated bypass is enabled"
    end

    if error_messages[:secret_scanning_validity_checks].present?
      messages << "Secret scanning must be enabled when secret scanning validity checks is enabled"
    end

    if error_messages[:secret_scanning_non_provider_patterns].present?
      messages << "Secret scanning must be enabled when secret scanning non-provider patterns is enabled"
    end

    "Invalid configuration: #{messages.join(', ')}"
  end

  def validate_attach_configuration!(target, data)
    if data["scope"] == "selected" && data["selected_repository_ids"].blank?
      deliver_error!(422, message: "No repository IDs were provided for the selected scope.")
    end

    if data["scope"] != "selected" && data["selected_repository_ids"].present?
      deliver_error!(422, message: "Repository IDs were provided for `#{data["scope"]}` scope. Use `selected` scope to attach specific repositories.")
    end

    if target.security_configurations_applying_or_blocked?
      deliver_error!(409, message: "Another enablement event is in progress. Applying this configuration is not available until it's finished.")
    end
  end

  def validate_parameters!(data)
    if GitHub.multi_tenant_enterprise? && data["secret_scanning_validity_checks"].present?
      deliver_error!(422, message: "Secret scanning validity checks cannot be set for multi-tenant enterprise.")
    elsif GitHub.enterprise? && data["dependency_graph"].present?
      deliver_error!(422, message: "Dependency graph cannot be set via configurations in GitHub Enterprise Server.")
    end

    if GitHub.enterprise?
      manager = SecurityProductsEnablement::SecurityProductsManager.new

      PARAMETER_VALUES_TO_RECORD_ENABLEMENT_ATTRIBUTES.keys.select { |f| data[f].present? }.each do |feature|
        error = if feature == "code_scanning_default_setup"
          !manager.code_scanning_default_setup_enabled?
        elsif feature == "secret_scanning" || feature == "secret_scanning_push_protection" || feature == "secret_scanning_delegated_bypass" || feature == "secret_scanning_validity_checks" || feature == "secret_scanning_non_provider_patterns"
          !manager.secret_scanning_enabled?
        else
          !manager.send("#{feature}_enabled?")
        end

        deliver_error!(422, message: "The requested security product is not installed: #{feature.humanize}") if error
      end
    end

    true
  end

  def validate_secret_scanning_delegated_bypass!(org, data)
    if data["secret_scanning_delegated_bypass"] == "enabled" &&
        (data["secret_scanning_delegated_bypass_options"].nil? ||
        data["secret_scanning_delegated_bypass_options"].empty?)
      deliver_error(422, message: "Delegated bypass reviewers list must be provided when delegated bypass is set to enabled")
    end

    if data["secret_scanning_delegated_bypass_options"].present? && !valid_reviewers_list?(org, data["secret_scanning_delegated_bypass_options"])
      deliver_error(400, message: "Invalid reviewers list provided for delegated bypass")
    end
  end

  def valid_reviewers_list?(org, options)
    return false unless options["reviewers"].present?
    options["reviewers"].each do |reviewer|
      return false unless SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(reviewer["reviewer_id"], reviewer["reviewer_type"], org)
    end
  end

  sig { params(scope: String).returns(T.nilable(String)) }
  def repository_query(scope)
    if scope == "all"
      "visibility:public,private,internal"
    elsif scope == "all_without_configurations"
      "configuration:None"
    elsif scope == "public"
      "visibility:public"
    elsif scope == "private_or_internal"
      "visibility:private,internal"
    else
      nil
    end
  end

  sig { params(obj: Business).void }
  def check_enterprise_security_config_ff!(obj)
    deliver_error!(404, message: "Not Found") unless SecurityProductsEnablement.enterprise_configs_enabled?(obj)
  end
end
