# typed: true
# frozen_string_literal: true

module Api::Serializer::CodeSecurityConfigurationsDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def code_security_configuration_hash(data, options)
    configuration = data.fetch(:configuration)
    org = data.fetch(:org)

    return nil if configuration.nil? || org.nil?

    html_url = config_html_url(configuration, org)

    target_type = configuration.global? ? "global" : "organization"

    config_hash(configuration, org, target_type, html_url)
  end

  def default_code_security_configurations_hash(data, options)
    defaults = data.fetch(:defaults)
    configurations = data.fetch(:configurations)
    org = data.fetch(:org)

    return nil if defaults.nil? || configurations.nil? || org.nil?

    # Create a hash mapping configuration id to its details for quick lookup
    configurations_hash = configurations.each_with_object({}) do |configuration, hash|
      html_url = config_html_url(configuration, org)

      target_type = configuration.global? ? "global" : "organization"

      hash[configuration.id] = config_hash(configuration, org, target_type, html_url)
    end

    # Combine defaults and configurations to form the final hash
    result = defaults.map do |default|
      config = configurations_hash[default.security_configuration_id]

      {
        default_for_new_repos: default_for_new_repos(default),
        configuration: config
      }
    end

    result
  end

  def default_for_new_repos(default)
    if default.default_for_new_public_repos && default.default_for_new_private_repos
      "all"
    elsif default.default_for_new_public_repos
      "public"
    elsif default.default_for_new_private_repos
      "private_and_internal"
    end
  end

  def config_html_url(configuration, org)
    if configuration.global?
      html_url("/organizations/#{org.display_login}/settings/security_products/configurations/view")
    else
      html_url("/organizations/#{org.display_login}/settings/security_products/configurations/edit/#{configuration.id}")
    end
  end

  def config_hash(configuration, org, target_type, html_url)
    hash = {
      id: configuration.id,
      target_type:,
      name: configuration.name,
      description: configuration.description,
      advanced_security: configuration.enable_ghas ? "enabled" : "disabled",
      dependency_graph: configuration.dependency_graph,
      dependency_graph_autosubmit_action: configuration.dependency_graph_autosubmit_action,
      dependency_graph_autosubmit_action_options: configuration.dependency_graph_autosubmit_action_options,
      dependabot_alerts: configuration.dependabot_alerts,
      dependabot_security_updates: configuration.dependabot_security_updates,
      code_scanning_default_setup: configuration.code_scanning,
      secret_scanning: configuration.secret_scanning,
      secret_scanning_push_protection: configuration.secret_scanning_push_protection,
      secret_scanning_non_provider_patterns: configuration.secret_scanning_non_provider_patterns,
    }

    hash.merge!({
      enforcement: configuration.enforcement(org) == :not_enforced ? "unenforced" : "enforced",
      url: url("/orgs/#{org.display_login}/code-security/configurations/#{configuration.id}"),
      html_url:,
      created_at: time(configuration.created_at),
      updated_at: time(configuration.updated_at),
    })

    security_products_manager = SecurityProductsEnablement::SecurityProductsManager.new

    if security_products_manager.private_vulnerability_reporting_enabled?
      hash[:private_vulnerability_reporting] = configuration.private_vulnerability_reporting
    end

    # Update this to check the manager once the manager includes validity checks
    unless GitHub.multi_tenant_enterprise? || GitHub.enterprise?
      hash[:secret_scanning_validity_checks] = configuration.secret_scanning_validity_checks
    end

    if GitHub.enterprise?
      hash.delete(:dependency_graph) unless security_products_manager.dependency_graph_enabled?
      hash.delete(:dependabot_alerts) unless security_products_manager.dependabot_alerts_enabled?
      hash.delete(:dependabot_security_updates) unless security_products_manager.dependabot_security_updates_enabled?
      hash.delete(:code_scanning_default_setup) unless security_products_manager.code_scanning_default_setup_enabled?
      hash.delete(:secret_scanning) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_push_protection) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_validity_checks) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_non_provider_patterns) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:dependency_graph_autosubmit_action) unless security_products_manager.dependency_graph_autosubmit_action_enabled?
      hash.delete(:dependency_graph_autosubmit_action_options) unless security_products_manager.dependency_graph_autosubmit_action_enabled?
    end

    hash
  end

  def code_security_configurations_hash(data, options)
    return nil unless data && data[:org]

    configurations = data.fetch(:configurations)
    org = data.fetch(:org)

    configurations.map do |configuration|
      code_security_configuration_hash({ configuration: configuration, org: org }, options)
    end
  end

  def code_security_configuration_repository(record, options)
    {
      status: record.state,
      repository: simple_repository_hash(record.repository, options),
    }
  end

  def code_security_configuration_default(data, options)
    {
      default_for_new_repos: data[:default_for_new_repos],
      configuration: code_security_configuration_hash(data, options),
    }
  end

  def code_security_configuration_for_repository(data, options)
    repo_security_config = data.delete(:repo_security_config)
    data[:configuration] = repo_security_config.security_configuration
    {
      status: repo_security_config.state,
      configuration: code_security_configuration_hash(data, options)
    }
  end
end
