# frozen_string_literal: true

require "github_helpers"
require "secret_fetcher"

class UpdateJobCredentialsSerializer < ActiveModel::Serializer
  # Maximum number of repos that can be accessed with a single token.
  # The number is a trade-off between chatty API calls to create multiple tokens
  # and minimizing the impact to the update configs cache of JIT-accesssible repos
  # when one or more repositories are no longer accessible.
  MAX_REPO_COUNT_PER_TOKEN = 100

  class CredentialsInvalid < StandardError; end

  attributes :id, :credentials

  def credentials
    registry_creds = [*github_access_creds, jit_access_creds].compact

    encrypted_registry_creds = serialized_credentials(update_config.registries)
    registry_creds.concat(decrypt_registry_secrets(update_config.repo, encrypted_registry_creds))

    # If we're on an enterprise setup and GitHub credentials haven't been
    # specified in a registry, include the ones specified in a special
    # Dependabot secret. This helps ensure we won't get rate-limited whilst
    # looking for metadata to generate the update.
    if Dependabot.enterprise? && registry_creds.none? { |c| DotcomRegistry.compatible_with?(c) }
      registry_creds << DotcomRegistry.new(update_config.repo).credentials
    end

    # If we're on a proxima setup and GitHub credentials haven't been
    # specified in a registry, include the ones specified in a special
    # Dependabot secret. This helps ensure we won't get rate-limited whilst
    # looking for metadata to generate the update.
    if Dependabot.proxima? && registry_creds.none? { |c| DotcomRegistry.compatible_with?(c) }
      registry_creds << DotcomRegistry.new(update_config.repo).credentials
    end

    registry_creds.compact
  end

  private

  EXPIRED_TOKEN_RESPONSE = { "expired_token" => nil }.freeze

  def update_config
    @update_config ||= object.update_config
  end

  def hostname
    Dependabot::Application.target_github_hostname(update_config.repo.account)
  end

  def account
    @account ||= update_config.repo.account
  end

  def serialized_credentials(registries)
    include_metadata = update_config.repo.monolith_feature_enabled?(:dependabot_metadata_in_credentials)
    registries.map { |registry| registry.serialized_credentials(include_metadata:) }
  rescue URI::InvalidURIError => e
    Dependabot::Logger.info(
      msg: "invalid credentials",
      "code.namespace": "UpdateJobCredentialsSerializer",
      "exception.message": e.message,
      **object.telemetry_attributes, # update_job attributes
    )
    raise CredentialsInvalid
  end

  def github_access_creds
    multi_github_access_token_map.map do |access_token, repos|
      {
        "type" => "git_source",
        "host" => hostname,
        "username" => "x-access-token",
        "password" => access_token,
        "accessible-repos" => repos,
      }.compact
    end
  end

  def multi_github_access_token_map
    return EXPIRED_TOKEN_RESPONSE unless account.current_installation_id

    repos = update_config.accessible_github_repos
    permissions = { contents: "read", metadata: "read" }

    repos.each_slice(MAX_REPO_COUNT_PER_TOKEN).reduce({}) do |accum, batch|
      token_slice = github_access_token_for_repos(batch, permissions)
      next accum if token_slice.nil?

      accum.merge(token_slice)
    end
  rescue GitHubHelpers::InvalidInstallationId
    SynchronizeAccountState.new(
      account: account,
      event_source: "api.get_update_job_credentials",
    ).run

    EXPIRED_TOKEN_RESPONSE
  end

  def github_access_token_for_repos(repos, permissions)
    token = GitHubHelpers.access_token_for(
      account: account,
      repo_ids: repos.map(&:github_id),
      permissions: permissions,
    )

    { token => repos.map(&:full_name) }
  rescue Octokit::UnprocessableEntity => e
    # Re-raise the error if the request is limited only to the update job's repo
    raise e if repos == [update_config.repo]

    # Remove the repos in this batch from the update config's known list of jit accessed repos.
    # This stored value is intended to be ephemeral, repos will be added back to the list
    # as they are accessed.
    update_config.remove_jit_accessed_internal_github_repo_ids(repos.map(&:github_id))

    # Only retry if the current repo batch includes the update config's repo, where the retry
    # is limited  to only request access for the update config's repo.
    return nil unless repos.include?(update_config.repo)

    repos = [update_config.repo]
    retry
  end

  def jit_access_creds
    {
      "type" => "jit_access",
      "credential-type" => "git_source",
      "host" => hostname,
      "endpoint" => "/update_jobs/#{object.id}/create_jit_access",
    }
  end

  def decrypt_registry_secrets(repo, registries)
    secret_names = extract_secret_names(registries)
    return registries if secret_names.empty?

    node_ids = github_node_ids(repo)

    decrypted = secret_fetcher.fetch(repo, node_ids[:owner_node_id], node_ids[:repo_node_id], *secret_names)
    replace_decrypted_secrets(registries, decrypted)
  end

  def extract_secret_names(registries)
    registries.map do |registry|
      registry.values.
        filter { |v| v.is_a?(String) }.
        map do |v|
          v.scan(/\${{\s*secrets\.(\w+)\s*}}/)
        end
    end.compact.flatten
  end

  def replace_decrypted_secrets(registries, decrypted)
    registries.each do |creds|
      creds.each do |k, val|
        next unless val.is_a?(String)

        decrypted.each do |name, plaintext|
          val = val.gsub(/\${{\s*secrets\.#{name}\s*}}/, plaintext&.strip)
        end
        creds[k] = val
      end
    end
  end

  def github_node_ids(repo)
    client = GitHubHelpers::ClientWithRetries.new(account: repo.account)
    {
      owner_node_id: client.user(repo.account.github_id).node_id,
      repo_node_id: client.repo(repo.github_id).node_id,
    }
  rescue Octokit::Unauthorized
    # Retry once to see if the error is transient for some reason
    attempt ||= 0
    attempt += 1
    retry if attempt <= 1

    # If we are unable to fetch node ids from GitHub, we cannot retrieve secrets
    raise SecretFetcher::SecretNotRetrieved, "for repository #{repo.name}"
  rescue GitHubHelpers::InvalidInstallationId
    raise SecretFetcher::SecretNotRetrieved, "for repository #{repo.name}"
  end

  def secret_fetcher
    Dependabot::Application.secret_fetcher
  end
end
