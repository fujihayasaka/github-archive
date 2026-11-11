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

    credentials = oidc_configs.map { |config| build_oidc_credential(config: config) }
    credentials += secret_credentials_for(
      secret_configs, repository: repository, app: private_registry_app, actor: actor, include_value: include_value
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
        configs: T::Array[PrivateRegistry::Configuration],
        repository: Repository,
        app: Integration,
        actor: T.nilable(User),
        include_value: T::Boolean,
      ).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])
    end
    def secret_credentials_for(configs, repository:, app:, actor:, include_value:)
      return [] if configs.empty?

      configs_by_name = configs.index_by(&:secret_name)

      org_secrets = Secrets.for_repository(
        repository,
        app: app,
        actor: actor,
        fetch_environments: false,
        include_value: include_value,
      ).fetch(:organization_secrets, [])

      secrets_by_name = T.let(
        org_secrets.index_by { |s| s[:name] },
        T::Hash[String, T::Hash[Symbol, String]],
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
        secret: T::Hash[Symbol, String],
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
        secret: T::Hash[Symbol, String],
        owner: User,
      ).returns(T.nilable(String))
    end
    def decrypted_secret_value(secret, owner:)
      return nil unless secret[:value].present?

      value = Base64.strict_decode64(T.must(secret[:value]))
      return value if GitHub.enterprise?

      encryption_key.open(value, scope: owner.next_global_id)
    end
  end
end
