# typed: strict
# frozen_string_literal: true

class Variables

  class Error < StandardError

    sig { returns(Integer) }
    attr_reader :status

    sig { returns(T.any(T::Hash[Symbol, T.untyped], GitHub::Options)) }
    attr_reader :options

    sig do
      params(
        msg: T.nilable(String),
        status: Integer,
        options: T.any(T::Hash[Symbol, T.untyped], GitHub::Options)
      ).void
    end
    def initialize(msg, status, options)
      @status = status
      @options = options
      super(msg)
    end
  end

  # Earthsmoke has been removed but we still need to support
  # embedding data for historical purposes. This is based on
  # https://github.com/github/earthsmoke/blob/main/client/ruby/lib/earthsmoke/embedding.rb
  sig { params(id: Integer, data: T.untyped).returns(String) }
  def self.embed(id, data)
    data = String.new(data, encoding: Encoding::ASCII_8BIT)
    [2, id, data].pack("CQ>a*")
  end

  sig do
    params(
      app: Integration,
      owner: T.any(User, Repository, Organization, Environment),
      actor: T.nilable(User)
    ).returns(T.untyped)
  end
  def self.for_app(app, owner:, actor:)
    resp = list(app: app, owner: owner, actor: actor)

    resp&.variables || []
  end

  sig do
    params(
      app: Integration,
      owner: T.any(Repository, Organization, Environment),
      actor: T.nilable(User),
      page: Integer,
      per_page: Integer
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.for_app_paginated(app, owner:, actor:, page:, per_page:)
    resp = list(app: app, owner: owner, actor: actor, page: page, per_page: per_page)

    {
      variables: resp&.variables || [],
      total_count: resp&.total_count || 0
    }
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      app: Integration,
      fetch_environments: T::Boolean,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.for_repository(repository, actor:, app:, fetch_environments: false)
    environments = fetch_environments && repository.can_use_environments? ? repository.environments : Environment.none
    environments = environments.limit(Repository::REPO_ENV_LIMIT) if repository.limit_environment_fetching?
    resp = list_repository(
      app: app,
      repository: repository,
      environments: environments,
      actor: actor,
    )

    {
      repository_variables: Array(resp&.repository_variables).map { |s| map_variable s },
      organization_variables: Array(resp&.organization_variables).map { |s| map_variable s },
      environment_variables: map_environment_variables(variables: Array(resp&.environment_variables), environments: environments)
    }
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      app: Integration,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.list_variable_names_for_repository(repository, actor:, app:)
    resp = list_repository(
      app: app,
      repository: repository,
      actor: actor,
      environments: [],
      include_value: false,
    )

    repository_variable_names = resp&.repository_variables.map(&:name)
    organization_variable_names = resp&.organization_variables.map(&:name)

    repository_variable_names.concat(Array(resp&.remaining_repo_var_names))
    organization_variable_names.concat(Array(resp&.remaining_org_var_names))

    {
      repository_variable_names: repository_variable_names,
      organization_variable_names: organization_variable_names,
    }
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      app: T.untyped,
      page: Integer,
      per_page: Integer
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.for_repository_environments(repository, actor:, app:, page:, per_page:)
    environments = repository.can_use_environments? ? repository.environments : Environment.none
    environments = environments.limit(Repository::REPO_ENV_LIMIT) if repository.limit_environment_fetching?

    return { environment_variables: [], total_count: 0 } if environments.empty?

    resp = make_varz_call(app, :list_for_owners) do
      GitHub::KredzClient::Varz.list_variables_for_owners(
        app: app,
        owners: environments,
        actor: actor,
        page: page,
        per_page: per_page,
      )
    end

    {
      environment_variables: map_environment_variables(variables: Array(resp&.variables), environments: environments) || [],
      total_count: resp&.total_count || 0
    }
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      app: Integration,
      page: Integer,
      per_page: Integer
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.for_repository_organizations(repository, actor:, app:, page:, per_page:)
    resp = list_repository_org_variables(repository, actor: actor, app: app, page: page, per_page: per_page)

    {
      organization_variables: Array(resp&.organization_variables).map { |s| map_variable s },
      total_count: resp&.total_count
    }
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      app: Integration,
      page: Integer,
      per_page: Integer
    ).returns(T.untyped)
  end
  def self.list_repository_org_variables(repository, actor:, app:, page:, per_page:)
    make_varz_call(app, :list_organization_variables_for_repository) do
      GitHub::KredzClient::Varz.list_org_variables_for_repository(
        app: app,
        repository: repository,
        actor: actor,
        page: page,
        per_page: per_page,
      )
    end
  end

  sig do
    params(
      name: String,
      owner: T.any(Repository, Organization, Environment),
      actor: T.nilable(User),
      app: Integration,
    ).returns(T.untyped)
  end
  def self.fetch(name:, owner:, actor:, app:)
    make_varz_call(app, :fetch) do
      GitHub::KredzClient::Varz.fetch_variable(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
      )
    end
  end

  sig do
    params(
      name: String,
      app: Integration,
      owner: T.any(Repository, Organization, Environment),
      actor: T.nilable(User),
      updated_name: String,
      value: String,
      visibility: Symbol,
      selected_repositories: T::Array[String],
    ).returns(T.untyped)
  end
  def self.update(name:, app:, owner:, actor:, updated_name:, value: "", visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_OWNER,  selected_repositories: [])
    result = make_varz_call(app, :update) do
      GitHub::KredzClient::Varz.update_variable(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        updated_key: updated_name,
        value: value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end

    variable_type, owner_type, owner_org, owner_repo, owner_env = determine_variable_type(owner)
    return result if variable_type.nil? || owner_type.nil? || [owner_org, owner_repo, owner_env].all?(nil)

    GlobalInstrumenter.instrument("#{variable_type}.update", {
      app: app.name,
      owner_type: owner_type,
      owner_org: owner_org,
      owner_repo: owner_repo,
      owner_env: owner_env,
      actor: actor,
      name: name,
      visibility: visibility,
      state: :UPDATED,
      updated_at: Time.now,
      updated_name: updated_name,
      varlen: Base64.strict_decode64(value).length,
    })

    result
  end

  sig do
    params(
      name: String,
      app: Integration,
      owner: T.any(Repository, Organization, Environment),
      actor: T.nilable(User),
      value: String,
      visibility: T.nilable(Symbol),
      selected_repositories: T::Array[String],
    ).returns(T.untyped)
  end
  def self.store(name:, app:, owner:, actor:, value:, visibility: GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_OWNER,  selected_repositories: [])
    # known twirp errors that we should not log any sentry errors for
    expected_errors = [:already_exists]
    result = make_varz_call(app, :store, expected_errors: expected_errors) do
      GitHub::KredzClient::Varz.store_variable(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        value: value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end

    variable_type, owner_type, owner_org, owner_repo, owner_env = determine_variable_type(owner)
    return result if variable_type.nil? || owner_type.nil? || [owner_org, owner_repo, owner_env].all?(nil)

    GlobalInstrumenter.instrument("#{variable_type}.create", {
      app: app.name,
      owner_type: owner_type,
      owner_org: owner_org,
      owner_repo: owner_repo,
      owner_env: owner_env,
      actor: actor,
      name: name,
      visibility: visibility,
      state: :CREATED,
      updated_at: Time.now,
      varlen: Base64.strict_decode64(value).length,
    })

    result
  end

  sig do
    params(
      name: String,
      owner: T.any(Repository, Organization, Environment),
      actor: T.nilable(User),
      app: Integration,
    ).returns(T.untyped)
  end
  def self.delete(name:, owner:, actor:, app:)
    result = make_varz_call(app, :delete) do
      GitHub::KredzClient::Varz.delete_variable(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
      )
    end

    variable_type, owner_type, owner_org, owner_repo, owner_env = determine_variable_type(owner)
    return result if variable_type.nil? || owner_type.nil? || [owner_org, owner_repo, owner_env].all?(nil)

    GlobalInstrumenter.instrument("#{variable_type}.remove", {
      app: app.name,
      owner_type: owner_type,
      owner_org: owner_org,
      owner_repo: owner_repo,
      owner_env: owner_env,
      actor: actor,
      name: name,
      state: :DELETED,
      updated_at: Time.now,
    })

    result
  end

  sig do
    params(
      app: Integration,
      owner: T.any(User, Repository, Organization, Environment),
      actor: T.nilable(User),
      page: Integer,
      per_page: Integer,
    ).returns(T.untyped)
  end
  def self.list(app:, owner:, actor:, page: 0, per_page: 0)
    make_varz_call(app, :list) do
      GitHub::KredzClient::Varz.list_variables(
        app: app,
        owner: owner,
        actor: actor,
        page: page,
        per_page: per_page,
      )
    end
  end

  sig do
    params(
      app: Integration,
      repository: Repository,
      environments: T.untyped,
      actor: T.nilable(User),
      include_value: T::Boolean,
    ).returns(T.untyped)
  end
  def self.list_repository(app:, repository:, environments:, actor:, include_value: true)
    make_varz_call(app, :list_repository) do
      GitHub::KredzClient::Varz.list_repository_variables(
        app: app,
        repository: repository,
        environments: environments,
        actor: actor,
        include_value: include_value,
      )
    end
  end

  sig do
    params(
      repository: Repository,
      app: Integration,
      environments: T.untyped,
    ).returns(T.untyped)
  end
  def self.variable_count_for_environments(repository, app:, environments:)
    return [] if environments.empty? || !repository.can_use_environments?
    result = make_varz_call(app, :get_variable_counts) do
      GitHub::KredzClient::Varz.get_variable_counts(
        app: app,
        owner_ids: GitHub.enterprise? ? environments.map(&:global_relay_id) : environments.map(&:next_global_id),
        owner_type: GitHub::KredzClient::Varz::VARIABLE_OWNER_ENVIRONMENT_TYPE,
      )
    end
    result.variable_counts || []
  end

  sig { params(variable: GitHub::Kredz::Services::Varz::Variable).returns(T.nilable(DateTime)) }
  def self.variable_updated_at(variable)
    return nil unless variable.updated_at || variable.created_at

    Time.at(variable.updated_at&.seconds || variable.created_at&.seconds).utc.to_datetime
  end

  sig { params(variable: GitHub::Kredz::Services::Varz::Variable).returns(T.nilable(DateTime)) }
  def self.variable_created_at(variable)
    return nil unless variable.created_at

    Time.at(variable.created_at&.seconds).utc.to_datetime
  end

  class << self

    private

    sig do
      params(
        app: Integration,
        action: Symbol,
        expected_errors: T::Array[Symbol],
        block: T.proc.returns(T.untyped),
      ).returns(T.untyped)
    end
    def make_varz_call(app, action, expected_errors: [], &block)
      start_time = GitHub::Dogstats.monotonic_time

      resp = TwirpHelper.rescue_from_twirp_errors("Variables", expected_errors: expected_errors, &block)
      GitHub.dogstats.timing_since("variables.varz.#{action}", start_time, tags: [
        "app:#{app.name}",
        "status:#{resp.status}",
        "succeeded:#{resp.call_succeeded?}",
      ])

      unless resp.call_succeeded?
        raise Error.new(resp&.options&.[](:message), resp&.status, resp&.options)
      end

      resp.value
    end

    sig do
      params(
        variables: T::Array[GitHub::Kredz::Services::Varz::Variable],
        environments: T.untyped,
      ).returns(T.untyped)
    end
    def map_environment_variables(variables:, environments:)
      return [] if variables.empty?

      environments_hash = environments.each_with_object({}) do |env, hash|
        env_global_id = GitHub.enterprise? ? env.global_relay_id : env.next_global_id
        hash[env_global_id] = env
      end

      variables.map do |variable|
        environment = environments_hash[variable.owner&.environment&.global_id]
        map_variable(variable).merge(environment_name: environment&.name, environment_id: environment&.id)
      end
    end

    sig { params(variable: GitHub::Kredz::Services::Varz::Variable).returns(T.untyped) }
    def map_variable(variable)
      {
        name: variable.name,
        created_at: variable_created_at(variable),
        updated_at: variable_updated_at(variable),
        value: variable.value,
      }
    end

    sig { params(owner: T.any(Repository, Organization, Environment)).returns(T::Array[T.untyped]) }
    def determine_variable_type(owner)
      case owner
      when ::Repository
        [:repository_variable, :REPOSITORY, nil, owner, nil]
      when ::Organization
        [:org_variable, :ORGANIZATION, owner, nil, nil]
      when ::Environment
        [:env_variable, :ENVIRONMENT, nil, nil, owner]
      end
    end
  end
end
