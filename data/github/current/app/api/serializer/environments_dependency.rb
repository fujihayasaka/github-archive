# typed: false
# frozen_string_literal: true

module Api::Serializer::EnvironmentsDependency
  # Creates a hash to be serialized to JSON.
  #
  # environment - Environment instance.
  # options     - Hash
  #
  # Returns a Hash if the Environment exists, or nil. Includes built-in protection rules and deployment branch policy. Does not include custom rules.
  def environment_hash_with_built_in_gates(environment, options = {})
    options = Api::SerializerOptions.from(options)
    hash = simple_environment_hash(environment, options)
    return hash if hash.nil?

    gates = environment.gates.reject { |gate| gate.type == "custom" }
    hash[:protection_rules] = gates_hash(gates, options)

    # eventually we might allow a mix of protected branches + custom rules
    # so we return two bools instead of an enum here
    if environment.repository.can_use_deployment_protected_branch?
      if environment.branch_policy_gate.present?
        is_protected_branch_policy = environment.branch_policy_gate_branch_protected?
        hash[:deployment_branch_policy] =
        {
          protected_branches: is_protected_branch_policy,
          custom_branch_policies: !is_protected_branch_policy
        }
      else
        hash[:deployment_branch_policy] = nil
      end
    end
    hash
  end

  def environments_hash(data, options)
    environments = data[:environments] || []
    environment_hashes = environments.map do |environment|
      environment_hash_with_built_in_gates(environment, options)
    end

    {
      total_count: data[:total_count],
      environments: environment_hashes,
    }
  end

  # Creates a hash from an Environment to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # environment - Environment instance
  #
  # Returns a Hash if the Environment exists, or nil
  def simple_environment_hash(environment, options = {})
    return nil unless environment
    repo = environment.repository

    {
      id:                  environment.id,
      node_id:             global_id_for(environment, options),
      name:                environment.name,
      url:                 url(environment_path(environment.name, environment.repository.name_with_owner_for_api(use: options[:serialize_login]))),
      html_url:            url_helpers.deployments_activity_log_url(user_id: repo.owner, repository: repo, environments_filter: environment.name, host: GitHub.host_name_with_tenant, protocol: GitHub.scheme),
      created_at:          time(environment.created_at),
      updated_at:          time(environment.updated_at),
      can_admins_bypass:   environment.can_admins_bypass?,
    }
  end

  def gates_hash(gates, options)
    gates.map do |gate|
      gate_hash(gate, options)
    end
  end

  def gate_hash(gate, options)
    type = gate.type
    type = "wait_timer" if type == "timeout"
    type = "required_reviewers" if type == "manual_approval"

    hash = {
      id:      gate.id,
      node_id: global_id_for(gate, options),
      type:    type,
    }

    if gate.type == "timeout"
      hash[:wait_timer] = gate.timeout
    elsif gate.type == "manual_approval"
      if gate.prevent_self_review?
        hash[:prevent_self_review] = true
      else
        hash[:prevent_self_review] = false
      end
      hash[:reviewers] = gate.gate_approvers.map do |approver|
        gate_reviewer_hash(approver, options)
      end
    end

    hash
  end

  def gate_reviewer_hash(gate_approver, options)
    approver = gate_approver.approver
    hash = {
      type: gate_approver.approver_type
    }

    if approver.is_a?(User)
      hash[:reviewer] = simple_user_hash(approver, options)
    elsif approver.is_a?(Team)
      hash[:reviewer] = team_hash(approver, options)
    end

    hash
  end

  def deployment_branch_policies_hash(data, options)
    branch_policies = data[:branch_policies] || []
    branch_policies_hashes = branch_policies.map do |branch_policy|
      deployment_branch_policy_hash(branch_policy, options)
    end

    {
      total_count: data[:total_count],
      branch_policies: branch_policies_hashes,
    }
  end

  def deployment_branch_policy_hash(branch_policy, options)
    hash = {
      id:      branch_policy.id,
      node_id: global_id_for(branch_policy, options),
      name: branch_policy.name
    }

    hash[:type] = branch_policy.is_tag_policy? ? "tag" : "branch"

    hash
  end

  def deployment_protection_rules_hash(data, options = {})
    gates = data[:gates] || []
    total_count = data[:total_count] || 0
    environment = data[:environment]
    integrations = data[:integrations]

    options = Api::SerializerOptions.from(options)

    custom_rules = gates.map do |rule|
      integration = integrations&.find { |integration| rule.integration&.id == integration.id }
      custom_rule_hash(rule, environment, integration, options)
    end

    {
      total_count: total_count,
      custom_deployment_protection_rules: custom_rules
    }
  end

  def custom_deployment_rule_integrations_hash(data, options = {})
    integrations = data[:integrations]
    total_count = data[:total_count] || 0

    options = Api::SerializerOptions.from(options)

    apps = integrations.map do |integration|
      custom_deployment_rule_integration_hash(integration, options)
    end

    {
      total_count: total_count,
      available_custom_deployment_protection_rule_integrations: apps
    }
  end

  def deployment_protection_rule_hash(data, options = {})
    gate = data[:gate]
    environment = data[:environment]
    integration = data[:integration]

    options = Api::SerializerOptions.from(options)

    custom_rule_hash(gate, environment, integration, options)
  end

  private

  def custom_rule_hash(rule, environment, integration, options)
    {
      id:            rule.id,
      node_id:       global_id_for(rule, options),
      app:           custom_deployment_rule_integration_hash(integration, options),
      enabled:       true
    }
  end

  def custom_deployment_rule_integration_hash(app, options = {})
    return {} unless app

    {
      id:               app.id,
      node_id:          global_id_for(app, options),
      slug:             app.slug,
      integration_url:  "#{GitHub.api_url}/apps/#{app.slug}"
    }
  end

  def environment_path(environment_name, repo_nwo)
    "/repos/#{repo_nwo}/environments/#{environment_name}"
  end

  EnvironmentFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Environment {
      id
      databaseId
      name
    }
  GRAPHQL

  def graphql_simple_environment_hash(environment, options = {})
    environment = EnvironmentFragment.new(environment)
    return nil unless environment

    hash = {
      id: environment.database_id,
      node_id: environment.id,
      name: environment.name,
    }

    if options.repo.present?
      hash[:url] = url(environment_path(environment.name, options.repo.name_with_owner_for_api(use: options[:serialize_login])))
      hash[:html_url] = url_helpers.deployments_activity_log_url(user_id: options.repo.owner, repository: options.repo, environments_filter: environment.name, host: GitHub.host_name_with_tenant, protocol: GitHub.scheme)
    end

    hash
  end
end
