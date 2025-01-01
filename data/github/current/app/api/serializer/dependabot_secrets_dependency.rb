# typed: true
# frozen_string_literal: true

module Api::Serializer::DependabotSecretsDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def dependabot_secrets_hash(data, options = {})
    data[:secrets] ||= []
    secret_hashes = data[:secrets].map do |secret|
      dependabot_secret_hash(secret)
    end

    {
      total_count: data[:total_count],
      secrets: secret_hashes,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # config  - a GitHub::Launch::Services::Credz::Credential
  #
  # Returns a Hash of the secret, or nil if nil is passed in.
  def dependabot_secret_hash(secret, options = {})
    return nil unless secret

    updated_at = secret.updated_at
    created_at = secret.created_at

    if updated_at.nil?
      updated_at = created_at
    end

    {
      name: secret.name,
      created_at: time(Time.at(created_at&.seconds || 0).utc.to_datetime),
      updated_at: time(Time.at(updated_at&.seconds || 0).utc.to_datetime),
    }
  end

  def dependabot_org_secrets_hash(data, _options = {})
    data[:secrets] ||= []
    secret_hashes = data[:secrets].map do |secret|
      dependabot_org_secret_hash({ secret: secret, org: data[:org] })
    end

    {
      total_count: data[:total_count],
      secrets: secret_hashes,
    }
  end

  def dependabot_org_secret_hash(data, options = {})
    secret = data[:secret]
    org = data[:org]

    secret_hash = dependabot_secret_hash(secret, options)
    return nil unless secret_hash

    secret_hash.tap do |hash|
      hash[:visibility] = GitHub::KredzClient::Credz::TO_VISIBILITY_MAP[secret.visibility]

      if secret.visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
        hash[:selected_repositories_url] = url("#{org_dependabot_secret_path(org, secret)}/repositories", options)
      end
    end
  end

  def dependabot_secret_repositories_hash(data, options = {})
    repository_hashes = (data[:repositories] || []).map do |repository|
      simple_repository_hash(repository, options)
    end

    {
      total_count: data[:total_count],
      repositories: repository_hashes,
    }
  end

  private

  def org_dependabot_secret_path(org, secret)
    "/orgs/#{org.display_login}/dependabot/secrets/#{secret.name}"
  end
end
