# typed: false
# frozen_string_literal: true

require "diet_earthsmoke"

class Secrets
  class Error < StandardError
    attr_reader :status, :options
    def initialize(msg, status, options)
      @status = status
      @options = options
      super(msg)
    end
  end

  # Earthsmoke has been removed but we still need to support
  # embedding data for historical purposes. This is based on
  # https://github.com/github/earthsmoke/blob/main/client/ruby/lib/earthsmoke/embedding.rb
  def self.embed(id, data)
    data = String.new(data, encoding: Encoding::ASCII_8BIT)
    [2, id, data].pack("CQ>a*")
  end

  def self.for_app(app, owner:, actor:)
    resp = list(app: app, owner: owner, actor: actor)

    resp&.credentials || []
  end

  def self.for_repository(repository, actor:, app:, fetch_environments: false, include_value: false)
    environments = fetch_environments && repository.can_use_environments? ? repository.environments : Environment.none
    environments = environments.limit(Repository::REPO_ENV_LIMIT) if repository.limit_environment_fetching?
    resp = list_repository(
      app: app,
      repository: repository,
      environments: environments,
      actor: actor,
      include_value: include_value,
    )

    {
      repository_secrets: Array(resp&.repository_secrets).map { |s| map_secret s },
      organization_secrets: Array(resp&.organization_secrets).map { |s| map_secret s },
      environment_secrets: map_environment_secrets(secrets: Array(resp&.environment_secrets), environments: environments)
    }
  end

  def self.fetch(name:, owner:, actor:, app:, include_value: false)
    make_kredz_call(app, :fetch) do
      GitHub::KredzClient::Credz.fetch_credential(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        include_value: include_value,
      )
    end
  end

  def self.update(name:, app:, owner:, actor:, value: "", visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER,  selected_repositories: [])
    result = make_kredz_call(app, :update) do
      GitHub::KredzClient::Credz.update_credential(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        value: value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end

    secret_type = determine_secret_type(owner)
    return result if secret_type.nil?

    GlobalInstrumenter.instrument("#{secret_type}.update", {
      app: app,
      owner: owner,
      actor: actor,
      name: name,
      selected_repositories: selected_repositories,
      state: "UPDATED",
    })

    result
  end

  # Store is used to create or update a credential
  def self.store(name:, app:, owner:, actor:, value:, visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER,  selected_repositories: [])
    # known twirp errors that we should not log any sentry errors for
    expected_errors = [:already_exists, :out_of_range]

    result = make_kredz_call(app, :store, expected_errors: expected_errors) do
      GitHub::KredzClient::Credz.store_credential(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        value: value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end

    secret_type = determine_secret_type(owner)
    return result if secret_type.nil?

    GlobalInstrumenter.instrument("#{secret_type}.create", {
      app: app,
      owner: owner,
      actor: actor,
      name: name,
      selected_repositories: selected_repositories,
      state: "CREATED",
    })

    result
  end

  # Create is used to create a new credential
  def self.create(name:, app:, owner:, actor:, value:, visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_OWNER,  selected_repositories: [])
    # known twirp errors that we should not log any sentry errors for
    expected_errors = [:already_exists, :out_of_range]

    result = make_kredz_call(app, :store, expected_errors: expected_errors) do
      GitHub::KredzClient::Credz.create_credential(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
        value: value,
        visibility: visibility,
        selected_repositories: selected_repositories,
      )
    end

    secret_type = determine_secret_type(owner)
    return result if secret_type.nil?

    GlobalInstrumenter.instrument("#{secret_type}.create", {
      app: app,
      owner: owner,
      actor: actor,
      name: name,
      selected_repositories: selected_repositories,
      state: "CREATED",
    })

    result
  end

  def self.delete(name:, owner:, actor:, app:)
    result = make_kredz_call(app, :delete) do
      GitHub::KredzClient::Credz.delete_credential(
        app: app,
        owner: owner,
        actor: actor,
        key: name,
      )
    end

    secret_type = determine_secret_type(owner)
    return result if secret_type.nil?

    GlobalInstrumenter.instrument("#{secret_type}.remove", {
      app: app,
      owner: owner,
      actor: actor,
      name: name,
      selected_repositories: [],
      state: "DELETED",
    })

    result
  end

  def self.list(app:, owner:, actor:)
    make_kredz_call(app, :list) do
      GitHub::KredzClient::Credz.list_credentials(
        app: app,
        owner: owner,
        actor: actor,
      )
    end
  end

  def self.list_repository(app:, repository:, environments:, actor:, include_value: false)
    make_kredz_call(app, :list_repository) do
      GitHub::KredzClient::Credz.list_repository_secrets(
        app: app,
        repository: repository,
        environments: environments,
        actor: actor,
        include_value: include_value
      )
    end
  end

  def self.secret_count_for_environments(repository, app:, environments:)
    return [] if environments.empty? || !repository.can_use_environments?
    result = make_kredz_call(app, :get_secret_counts) do
      GitHub::KredzClient::Credz.get_secret_counts(
        app: app,
        owner_ids: GitHub.enterprise? ? environments.map(&:global_relay_id) : environments.map(&:next_global_id),
        owner_type: GitHub::KredzClient::Credz::CREDENTIAL_OWNER_ENVIRONMENT_TYPE,
      )
    end
    result.secret_counts || []
  end

  def self.github_public_key(owner:, key_name:)
    begin
      version = DietEarthsmoke::Key.new(key_name).current_key(scope: owner.next_global_id)

      encoded = Base64.strict_encode64(version.public_key)
      [version.id, encoded]
    rescue DietEarthsmoke::KeyParseError
      ["", ""]
    end
  end

  def self.secret_updated_at(secret)
    return nil unless secret.updated_at || secret.created_at

    Time.at(secret.updated_at&.seconds || secret.created_at&.seconds).utc.to_datetime
  end

  def self.secret_created_at(secret)
    return nil unless secret.created_at

    Time.at(secret.created_at&.seconds).utc.to_datetime
  end

  class << self
    private

    def make_kredz_call(app, action, expected_errors: [], &block)
      start_time = GitHub::Dogstats.monotonic_time

      resp = TwirpHelper.rescue_from_twirp_errors("Secrets", expected_errors: expected_errors, &block)
      GitHub.dogstats.timing_since("secrets.kredz.#{action}", start_time, tags: [
        "app:#{app.name}",
        "status:#{resp.status}",
        "succeeded:#{resp.call_succeeded?}",
      ])

      unless resp.call_succeeded?
        raise Error.new(resp&.options&.[](:message), resp&.status, resp&.options)
      end

      resp.value
    end

    def secrets_for_environment(environment, actor, app)
      resp = list(app: app, owner: environment, actor: actor)

      Array(resp&.credentials).map { |s| map_environment_secret(environment: environment, secret: s) }
    end

    def map_environment_secrets(secrets:, environments:)
      return [] if secrets.empty?

      environments_hash = environments.each_with_object({}) do |env, hash|
        env_global_id = GitHub.enterprise? ? env.global_relay_id : env.next_global_id
        hash[env_global_id] = env
      end

      secrets.map do |secret|
        environment = environments_hash[secret.owner.environment&.global_id]
        map_secret(secret).merge(environment_name: environment&.name, environment_id: environment&.id)
      end
    end

    def map_secret(secret)
      s = {
        name: secret.name,
        created_at: secret_created_at(secret),
        updated_at: secret_updated_at(secret),
      }

      if secret.value.present?
        s[:value] = secret.value
      end

      s
    end

    def determine_secret_type(owner)
      case owner
      when ::Repository
        :repository_secret
      when ::Organization
        :org_secret
      when ::User
        :user_secret
      end
    end
  end
end
