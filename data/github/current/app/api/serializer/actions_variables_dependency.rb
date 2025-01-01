# typed: strict
# frozen_string_literal: true

module Api::Serializer::ActionsVariablesDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  # Creates a Hash to be serialized to JSON.
  #
  # variable  - a GitHub::Kredz::Services::Varz::Variable
  #
  # Returns a Hash of the variable, or nil if nil is passed in.
  sig do
    params(
      variable: T.untyped,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def actions_variable_hash(variable, options = {})
    return nil unless variable

    updated_at = variable.updated_at
    created_at = variable.created_at

    if updated_at.nil?
      updated_at = created_at
    end

    hash = {
      name: variable.name,
      value: Base64.strict_decode64(variable.value),
      created_at: time(Time.at(created_at&.seconds || 0).utc.to_datetime),
      updated_at: time(Time.at(updated_at&.seconds || 0).utc.to_datetime),
    }

    hash
  end

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def actions_variables_hash(data, options = {})
    data[:variables] = data[:variables] || []
    variable_hashes = data[:variables].map do |variable|
      actions_variable_hash(variable)
    end

    {
      variables: variable_hashes,
      total_count: data[:total_count],
    }
  end

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def actions_org_variable_hash(data, options = {})
    variable = data[:variable]
    org = data[:org]

    variable_hash = actions_variable_hash(variable, options)
    return nil unless variable_hash

    variable_hash.tap do |hash|
      hash[:visibility] = GitHub::KredzClient::Varz::TO_VISIBILITY_MAP[variable.visibility]

      if variable.visibility == GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
        hash[:selected_repositories_url] = url("#{org_actions_variable_path(org, variable)}/repositories", options)
      end
    end
  end

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      _options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options) # unused
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def actions_org_variables_hash(data, _options = {})
    data[:variables] = data[:variables] || []
    variable_hashes = data[:variables].map do |variable|
      actions_org_variable_hash({ variable: variable, org: data[:org] })
    end

    {
      total_count: data[:total_count],
      variables: variable_hashes,
    }
  end

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def actions_variable_repositories_hash(data, options = {})
    repository_hashes = (data[:repositories] || []).map do |repository|
      simple_repository_hash(repository, options)
    end

    {
      total_count: data[:total_count],
      repositories: repository_hashes,
    }
  end

  sig do
    params(
      org: Organization,
      variable: GitHub::Kredz::Services::Varz::Variable
    ).returns(String)
  end
  def org_actions_variable_path(org, variable)
    "/orgs/#{org.name}/actions/variables/#{variable.name}"
  end
end
