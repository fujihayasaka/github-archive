# typed: true
# frozen_string_literal: true

module Api::Serializer::CodeSecurityConfigurationsDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def code_security_configuration_hash(data, options)
    configuration = data.fetch(:configuration)
    target = data.fetch(:target)
    actor = data.fetch(:actor, nil)

    return nil if configuration.nil? || target.nil?

    config_hash(configuration, target, actor)
  end

  def default_code_security_configurations_hash(data, options)
    defaults = data.fetch(:defaults)
    configurations = data.fetch(:configurations)
    target = data.fetch(:target)
    actor = data.fetch(:actor, nil)

    return nil if defaults.nil? || configurations.nil? || target.nil?

    # Create a hash mapping configuration id to its details for quick lookup
    configurations_hash = configurations.each_with_object({}) do |configuration, hash|
      hash[configuration.id] = config_hash(configuration, target, actor)
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

  def config_html_url(configuration, target)
    target = configuration.global? ? target : configuration.target

    if target.is_a? Business
      if configuration.global?
        html_url("/enterprises/#{target.display_login}/settings/security_analysis/configurations/#{configuration.id}/view")
      else
        html_url("/enterprises/#{target.display_login}/settings/security_analysis/configurations/#{configuration.id}/edit")
      end
    elsif target.is_a? Organization
      if configuration.global?
        html_url("/organizations/#{target.display_login}/settings/security_products/configurations/view/#{configuration.id}")
      else
        html_url("/organizations/#{target.display_login}/settings/security_products/configurations/edit/#{configuration.id}")
      end
    end
  end

  def resource_url(configuration, target)
    target = configuration.global? ? target : configuration.target

    if target.is_a? Business
      url("/enterprises/#{target.display_login}/code-security/configurations/#{configuration.id}")
    elsif target.is_a? Organization
      url("/orgs/#{target.display_login}/code-security/configurations/#{configuration.id}")
    end
  end

  sig do
    params(
      configuration: SecurityConfiguration,
      target: T.any(Business, Organization),
      actor: T.nilable(User)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def config_hash(configuration, target, actor)
    target_type =
      if configuration.global?
        "global"
      elsif configuration.target.is_a? Business
        "enterprise"
      elsif configuration.target.is_a? Organization
        "organization"
      end

    hash = {
      id: configuration.id,
      target_type:,
      name: configuration.name,
      description: configuration.description,
      advanced_security: advanced_security_field(configuration),
      dependency_graph: configuration.dependency_graph,
      dependency_graph_autosubmit_action: configuration.dependency_graph_autosubmit_action,
      dependency_graph_autosubmit_action_options: configuration.dependency_graph_autosubmit_action_options,
      dependabot_alerts: configuration.dependabot_alerts,
      dependabot_security_updates: configuration.dependabot_security_updates,
    }

    hash.merge!({ code_scanning_options: configuration.code_scanning_general_options }) if configuration.code_scanning_general_options.present?

    hash.merge!({
      code_scanning_default_setup: configuration.code_scanning,
      code_scanning_default_setup_options: configuration.code_scanning_default_setup_options,
      code_scanning_delegated_alert_dismissal: configuration.code_scanning_delegated_alert_dismissal,
      secret_scanning: configuration.secret_scanning,
      secret_scanning_push_protection: configuration.secret_scanning_push_protection,
      secret_scanning_delegated_bypass: configuration.secret_scanning_delegated_bypass,
      secret_scanning_non_provider_patterns: configuration.secret_scanning_non_provider_patterns,
      secret_scanning_delegated_alert_dismissal: configuration.secret_scanning_delegated_alert_dismissal,
      enforcement: configuration.enforcement(target) == :not_enforced ? "unenforced" : "enforced",
      url: resource_url(configuration, target),
      html_url: config_html_url(configuration, target),
      created_at: time(configuration.created_at),
      updated_at: time(configuration.updated_at),
    })

    security_products_manager = SecurityProductsEnablement::SecurityProductsManager.new

    if security_products_manager.private_vulnerability_reporting_enabled?
      hash[:private_vulnerability_reporting] = configuration.private_vulnerability_reporting
    end

    # Update this to check the manager once the manager includes validity checks
    if GitHub.secret_scanning_validity_checks_available_on_instance?
      hash[:secret_scanning_validity_checks] = configuration.secret_scanning_validity_checks
    end

    unless GitHub.enterprise?
      hash[:secret_scanning_generic_secrets] = configuration.secret_scanning_generic_secrets

    end

    if configuration.secret_scanning_delegated_bypass == "enabled" && target.is_a?(Organization) && actor
      reviewers, err = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(target, actor, security_configuration_id: configuration.id)
      if err.nil? && !reviewers.nil?
        reviewers = reviewers.map do |reviewer|
          {
            reviewer_id: reviewer.reviewer_id,
            reviewer_type: reviewer.reviewer_type,
            security_configuration_id: reviewer.security_configuration_id,
          }
        end
        hash[:secret_scanning_delegated_bypass_options] = { reviewers: }
      end
    end

    if GitHub.enterprise?
      hash.delete(:dependency_graph) unless security_products_manager.dependency_graph_enabled?
      hash.delete(:dependabot_alerts) unless security_products_manager.dependabot_alerts_enabled?
      hash.delete(:dependabot_security_updates) unless security_products_manager.dependabot_security_updates_enabled?
      hash.delete(:code_scanning_options) unless security_products_manager.code_scanning_default_setup_enabled?
      hash.delete(:code_scanning_default_setup) unless security_products_manager.code_scanning_default_setup_enabled?
      hash.delete(:code_scanning_default_setup_options) unless security_products_manager.code_scanning_default_setup_enabled?
      hash.delete(:code_scanning_delegated_alert_dismissal) unless security_products_manager.code_scanning_delegated_alert_dismissal_enabled?
      hash.delete(:secret_scanning) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_push_protection) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_delegated_bypass) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_delegated_bypass_options) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_validity_checks) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_non_provider_patterns) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_generic_secrets) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:secret_scanning_delegated_alert_dismissal) unless security_products_manager.secret_scanning_enabled?
      hash.delete(:dependency_graph_autosubmit_action) unless security_products_manager.dependency_graph_autosubmit_action_enabled?
      hash.delete(:dependency_graph_autosubmit_action_options) unless security_products_manager.dependency_graph_autosubmit_action_enabled?
    end

    hash
  end

  def advanced_security_field(configuration)
    return "enabled" if configuration.enable_ghas \
      || (configuration.code_security_sku_enabled && configuration.secret_protection_sku_enabled)
    return "code_security" if configuration.code_security_sku_enabled
    return "secret_protection" if configuration.secret_protection_sku_enabled

    "disabled"
  end

  def code_security_configurations_hash(data, options)
    return nil unless data && data[:target]

    configurations = data.fetch(:configurations)
    target = data.fetch(:target)
    actor = data.fetch(:actor, nil)

    configurations.map do |configuration|
      code_security_configuration_hash({ configuration: configuration, target: target, actor: actor }, options)
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
