# typed: strict
# frozen_string_literal: true

module PrivateRegistry

  sig do
    params(
      repository: Repository,
      actor: T.nilable(User),
      include_value: T::Boolean,
    ).returns(T::Array[T::Hash[Symbol, String]])
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
    org_configs_map = Hash[org_configs.map { |c| [c.secret_name, c] }]

    org_secrets = T.let(
      Secrets.for_repository(
        repository,
        app: private_registry_app,
        actor: actor,
        fetch_environments: false,
        include_value: include_value,
      ).fetch(:organization_secrets, []),
      T::Array[T::Hash[Symbol, String]],
    )
    org_secrets_map = Hash[org_secrets.map { |s| [T.must(s[:name]), s] }]

    secret_names = org_configs_map.keys & org_secrets_map.keys
    secret_names.map do |name|
      build_credential(
        config: T.must(org_configs_map[name]),
        secret: T.must(org_secrets_map[name]),
      )
    end
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

    # Accepts a private registry configuration and a secret, as a hash retrieved from Credz,
    # and returns a hash of credentials suitable for authenticating with a private registry
    # via, e.g., the dependabot-update-job-proxy server.
    sig do
      params(
        config: PrivateRegistry::Configuration,
        secret: T::Hash[Symbol, String],
      ).returns(T::Hash[Symbol, String])
    end
    def build_credential(config:, secret:)
      credential = {
        type: config.registry_type,
        url: config.url,
      }
      secret_value = decrypted_secret_value(secret, owner: config.owner)

      case config.registry_type
      when "maven_repository", "nuget_feed", "goproxy_server"
        credential[:username] = config.username if config.username.present?
        credential[:password] = secret_value if secret_value.present?
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
