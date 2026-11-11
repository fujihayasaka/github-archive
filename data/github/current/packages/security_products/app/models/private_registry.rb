# typed: strict
# frozen_string_literal: true

module PrivateRegistry
  PASSWORD_TYPES = %w[
    maven_repository nuget_feed goproxy_server composer_repository docker_registry git_source helm_registry
  ].freeze

  # TOKEN_TYPES that support username+password and combine them as "username:password"
  TOKEN_TYPES_WITH_COMBINED_AUTH = %w[
    npm_registry rubygems_server python_index
  ].freeze

  # TOKEN_TYPES that only support a token field
  TOKEN_TYPES = %w[
    cargo_registry pub_repository terraform_registry
  ].freeze

  # AUTH_KEY_TYPES = %w[hex_repository hex_organization].freeze

  sig { params(owner: User).returns(String) }
  def self.oidc_placeholder_secret_value(owner)
    value = if GitHub.enterprise?
      "oidc"
    else
      DietEarthsmoke::Key.new(Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS).seal("oidc", scope: owner.next_global_id)
    end
    Base64.strict_encode64(value)
  end

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      include_value: T::Boolean,
    ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
  end
  def self.credentials_for_repository(repository, actor:, include_value: false)
    private_registry_app = app
    if private_registry_app.nil?
      GitHub.logger.error(
      "Failed to find private registry secrets integration",
      "code.function" => "PrivateRegistry.credentials_for_repository",
      "gh.repo.id" => repository.id
      )
      return []
    end

    org = T.must(repository.owner)
    org_configs = PrivateRegistry::Configuration.for_organization(org).order(:id)

    oidc_configs, secret_configs = org_configs.partition(&:oidc?)

    return [] if oidc_configs.empty? && secret_configs.empty?

    # Fetch org secrets visible to this repository from Kredz once, shared by both paths.
    # OIDC configs also store a placeholder secret in Kredz with visibility/selected_repositories,
    # so we filter them the same way to enforce repository scoping.
    # Secret values are only needed for secret-backed configs; OIDC scoping only needs
    # secret metadata (names/visibility).
    visible_org_secrets = visible_org_secrets_for(
      repository: repository,
      app: private_registry_app,
      actor: actor,
      include_value: include_value && secret_configs.any?,
    )

    credentials = oidc_credentials_for(oidc_configs, visible_org_secrets: visible_org_secrets)
    credentials += secret_credentials_for(
      secret_configs, visible_org_secrets: visible_org_secrets,
    )
    credentials
  rescue Secrets::Error => e
    GitHub.logger.error(
      "Failed to list private registry secrets for repository",
      "code.function" => "PrivateRegistry.credentials_for_repository",
      "exception.message" => "[#{e.status}] #{e.message}",
      "exception.type" => e.class.name,
      "gh.repo.id" => repository.id,
    )

    []
  end

  class << self
    private

    sig { returns(T.nilable(Integration)) }
    def app
      # The app should always be installed, but making the return type T.nilable(Integration)
      # ensures that we handle the case where it is not.
      Apps::Privileged.integration(:private_registry_secrets)
    end

    sig { returns(DietEarthsmoke::Key) }
    def encryption_key
      DietEarthsmoke::Key.new(Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS)
    end

    sig do
      params(
        repository: Repository,
        app: Integration,
        actor: T.nilable(User),
        include_value: T::Boolean,
      ).returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def visible_org_secrets_for(repository:, app:, actor:, include_value:)
      Secrets.for_repository(
        repository,
        app: app,
        actor: actor,
        fetch_environments: false,
        include_value: include_value,
      ).fetch(:organization_secrets, [])
    end

    sig do
      params(
        configs: T::Array[PrivateRegistry::Configuration],
        visible_org_secrets: T::Array[T::Hash[Symbol, T.untyped]],
      ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
    end
    def oidc_credentials_for(configs, visible_org_secrets:)
      return [] if configs.empty?

      visible_secret_names = T.let(
        visible_org_secrets.filter_map { |s| T.cast(s[:name], T.nilable(String)) }.to_set,
        T::Set[String],
      )

      configs.filter_map do |config|
        next unless visible_secret_names.include?(config.secret_name)

        build_oidc_credential(config: config)
      end
    end

    sig do
      params(
        configs: T::Array[PrivateRegistry::Configuration],
        visible_org_secrets: T::Array[T::Hash[Symbol, T.untyped]],
      ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
    end
    def secret_credentials_for(configs, visible_org_secrets:)
      return [] if configs.empty?

      configs_by_name = configs.index_by(&:secret_name)

      secrets_by_name = T.let(
        visible_org_secrets.index_by { |s| T.cast(s[:name], String) },
        T::Hash[String, T::Hash[Symbol, T.untyped]],
      )

      matched_names = configs_by_name.keys & secrets_by_name.keys
      matched_names.map do |name|
        build_credential(
          config: configs_by_name[name],
          secret: T.must(secrets_by_name[name]),
        )
      end
    end

    # Accepts a private registry configuration and a secret, as a hash retrieved from Credz,
    # and returns a hash of credentials suitable for authenticating with a private registry
    # via, e.g., the dependabot-update-job-proxy server.
    sig do
      params(
        config: PrivateRegistry::Configuration,
        secret: T::Hash[Symbol, T.untyped],
      ).returns(T::Hash[Symbol, T.any(String, T::Boolean)])
    end
    def build_credential(config:, secret:)
      credential = {
        type: config.registry_type,
        url: config.url,
        "replaces-base": config.replaces_base
      }
      secret_value = decrypted_secret_value(secret, owner: config.owner)

      case config.registry_type
      when *PASSWORD_TYPES
        # For PASSWORD_TYPES, keep username and password separate
        credential[:username] = config.username if config.username.present?
        credential[:password] = secret_value if secret_value.present?
      when *TOKEN_TYPES_WITH_COMBINED_AUTH
        # These registry types support username+password, and when both are present,
        # combine them as username:password for HTTP Basic Auth (matches what
        # Dependabot API's Registry model does for repo-level registries)
        if config.username.present? && secret_value.present?
          credential[:token] = "#{config.username}:#{secret_value}"
        else
          credential[:username] = config.username if config.username.present?
          credential[:token] = secret_value if secret_value.present?
        end
      when *TOKEN_TYPES
        # only support token, not username+password
        credential[:token] = secret_value if secret_value.present?
      # when *AUTH_KEY_TYPES
      #   credential["auth-key"] = secret_value if secret_value.present?
      else
        raise "Unknown registry type: #{config.registry_type}"
      end

      credential
    end

    sig do
      params(
        config: PrivateRegistry::Configuration,
      ).returns(T::Hash[Symbol, T.any(String, T::Boolean)])
    end
    def build_oidc_credential(config:)
      credential = {
        type: config.registry_type,
        url: config.url,
        "replaces-base": config.replaces_base,
      }

      valid_fields = PrivateRegistry::Configuration::OIDC_CONFIG_FIELDS.fetch(config.auth_type, [])
      (config.oidc_config || {}).each do |key, value|
        next if value.blank? || valid_fields.exclude?(key)
        credential[key.dasherize.to_sym] = value
      end

      credential
    end

    sig do
      params(
        secret: T::Hash[Symbol, T.untyped],
        owner: User,
      ).returns(T.nilable(String))
    end
    def decrypted_secret_value(secret, owner:)
      secret_value = T.cast(secret[:value], T.nilable(String))
      return nil unless secret_value.present?

      value = Base64.strict_decode64(secret_value)
      return value if GitHub.enterprise?

      encryption_key.open(value, scope: owner.next_global_id)
    end
  end
end
