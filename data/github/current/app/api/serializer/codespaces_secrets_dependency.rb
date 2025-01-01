# typed: true
# frozen_string_literal: true

module Api::Serializer::CodespacesSecretsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def repo_codespaces_secrets_hash(data, options = {})
    data[:secrets] = data[:secrets] || []
    secret_hashes = data[:secrets].map do |secret|
      repo_codespaces_secret_hash(secret)
    end

    {
      total_count: data[:total_count],
      secrets: secret_hashes,
    }
  end

  def repo_codespaces_secret_hash(secret, options = {})
    return nil unless secret

    updated_at = secret.updated_at
    created_at = secret.created_at

    if updated_at.nil?
      updated_at = created_at
    end

    hash = {
      name: secret.name,
      created_at: time(Time.at(created_at&.seconds || 0).utc.to_datetime),
      updated_at: time(Time.at(updated_at&.seconds || 0).utc.to_datetime),
    }

    hash
  end

  def codespaces_user_secrets_hash(data, _options = {})
    data[:secrets] = data[:secrets] || []
    secret_hashes = data[:secrets].map do |secret|
      codespaces_user_secret_hash(secret, org: data[:org])
    end

    {
      total_count: data[:total_count],
      secrets: secret_hashes,
    }
  end
  alias :codespaces_org_secrets_hash :codespaces_user_secrets_hash

  def codespaces_user_secret_hash(secret, options = {}, org: nil)
    secret_hash = codespaces_secret_hash(secret, options)

    return nil unless secret_hash

    secret_hash.tap do |hash|
      hash[:visibility] = GitHub::KredzClient::Credz::TO_VISIBILITY_MAP[secret.visibility]

      if secret.visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
        if !org.nil?
          if FeatureFlag.vexi.enabled?(:codespaces_org_secrets_display_login_fix, default: false)
            hash[:selected_repositories_url] = url("/orgs/#{org.display_login}/codespaces/secrets/#{secret.name}/repositories", options)
          else
            hash[:selected_repositories_url] = url("/orgs/#{org.name}/codespaces/secrets/#{secret.name}/repositories", options)
          end
        else
          hash[:selected_repositories_url] = url("/user/codespaces/secrets/#{secret.name}/repositories", options)
        end
      end
    end
  end

  alias :codespaces_org_secret_hash :codespaces_user_secret_hash

  def codespaces_user_secret_repositories_hash(data, options = {})
    {
      repositories: data[:repositories].map do |r|
                      simple_repository_hash(r, global_id_selection: { user_preference: false, user_opt_out: false })
                    end,
      total_count: data[:total_count]
    }
  end

  private

  def codespaces_secret_hash(secret, options = {})
    return nil unless secret

    updated_at = secret.updated_at
    created_at = secret.created_at

    if updated_at.nil?
      updated_at = created_at
    end

    hash = {
      name: secret.name,
      created_at: created_at,
      updated_at: updated_at,
    }

    hash
  end

  def codespaces_secret_repositories_hash(data, options = {})
    repository_hashes = (data[:repositories] || []).map do |repository|
      simple_repository_hash(repository, options)
    end

    {
      total_count: data[:total_count],
      repositories: repository_hashes,
    }
  end
end
