# frozen_string_literal: true

require "ostruct"
require "diet_earthsmoke"
require "github-launch"
require "github-launch/hmac_client_interceptor"

class SecretFetcher
  class SecretNotFound < StandardError; end
  class SecretNotValid < StandardError; end
  class SecretNotRetrieved < StandardError; end

  # From https://github.com/github/github/blob/3cb86ff96793e863d18a0cc7e84c0b25f5ddc5b7/lib/platform/earthsmoke_keys.rb#L16
  EARTHSMOKE_KEY_NAME = "dependabot-secrets-key"

  def initialize(github_integration_node_id:, kredz:, global_id_api_client:)
    @diet_earthsmoke_key = DietEarthsmoke::Key.new(EARTHSMOKE_KEY_NAME) unless Dependabot.enterprise?
    @github_integration_node_id = github_integration_node_id
    @kredz = kredz
    @global_id_api_client = global_id_api_client
  end

  def fetch(repo, owner_github_node_id, repo_github_node_id, *secret_names)
    # Get the next_global_id for both the repo and its owner
    repo_next_global_id = next_global_id(repo_github_node_id)
    owner_next_global_id = next_global_id(owner_github_node_id)

    begin
      # Fetch all secrets available in the repo
      repo_secrets = repo_secrets(repo, owner_next_global_id, repo_next_global_id)
      raise SecretNotRetrieved, "for repository #{repo.name}" if repo_secrets.nil?

      # Select and decrypt the selected keys:
      Hash[secret_names.map do |name|
        secret = repo_secrets[name]
        raise SecretNotFound, name unless secret

        [name, decrypt(secret)]
      end]
    rescue StandardError => e
      log_error(e)
      raise_specific_error(e, repo)
    end
  end

  private

  def repo_secrets(repo, owner_github_node_id, repo_github_node_id)
    res = @kredz.list_secrets_for_repository(
      GitHub::Launch::Services::Credz::ListSecretsForRepositoryRequest.new(
        repository: repo_with_owner(repo, owner_github_node_id, repo_github_node_id),
        integration: @github_integration_node_id,
        is_private: repo.private?,
        include_value: true,
      ),
    )

    # Override organizations secrets with repo secrets:
    org_secrets = res.data&.organization_secrets&.index_by(&:name)
    repo_secrets = res.data&.repository_secrets&.index_by(&:name)
    org_secrets&.merge(repo_secrets)
  end

  def repo_with_owner(repo, owner_github_node_id, repo_github_node_id)
    GitHub::Launch::Services::Credz::RepositoryWithOwner.new(
      repository: GitHub::Launch::Services::Credz::Repository.new(
        global_id: repo_github_node_id
      ),
      owner: credential_owner_for(repo.account, owner_github_node_id),
    )
  end

  # rubocop:disable Metrics/MethodLength
  # https://github.com/github/github/blob/1fd0501589e1e96961d66cd54a462b2b98d5d4d4/lib/github/launch_client/credz.rb#L227
  def credential_owner_for(owner, owner_github_node_id)
    case owner
    when Repo
      GitHub::Launch::Services::Credz::CredentialOwner.new(
        repository: GitHub::Launch::Services::Credz::Repository.new(
          global_id: owner_github_node_id
        ),
      )
    when Account
      if owner.org?
        GitHub::Launch::Services::Credz::CredentialOwner.new(
          organization: GitHub::Launch::Services::Credz::Organization.new(
            global_id: owner_github_node_id
          ),
        )
      elsif owner.user?
        GitHub::Launch::Services::Credz::CredentialOwner.new(
          user: GitHub::Launch::Services::Credz::User.new(
            global_id: owner_github_node_id
          ),
        )
      else
        raise "unknown credential owner"
      end
    end
  end
  # rubocop:enable Metrics/MethodLength

  def decrypt(secret)
    if Dependabot.enterprise?
      # Kredz stores secrets unencrypted in GHES, see: https://github.com/github/github/pull/138627
      Base64.strict_decode64(secret.value)
    else
      ciphertext = Base64.decode64(secret.value)
      scope = if secret.owner.repository
                secret.owner.repository.global_id
              elsif secret.owner.organization
                secret.owner.organization.global_id
              else
                raise "unknown secret owner"
              end

      @diet_earthsmoke_key.open(ciphertext, scope: scope)
    end
  rescue DietEarthsmoke::CipherError
    raise SecretNotValid, secret.name
  end

  def next_global_id(global_relay_id)
    @global_id_api_client.get_github_next_global_id(global_relay_id)
  end

  def log_error(err)
    Dependabot::Logger.error(
      msg: err.message,
      "code.namespace": self.class.name,
      "exception.type": err.class,
      "exception.message": err.message,
      "exception.stacktrace": err.backtrace,
    )
  end

  def raise_specific_error(error, repo)
    case error
    when SecretNotFound
      raise SecretNotFound, error.message
    when SecretNotRetrieved
      raise SecretNotRetrieved, "Failed to fetch secrets for repository #{repo.name}"
    when SecretNotValid
      raise SecretNotValid, error.message
    else
      raise "Unhandled error type: #{error.class}"
    end
  end
end
