# typed: true
# frozen_string_literal: true

module Codespaces
  class GetPrebuildSecrets < Command
    class Error < Codespaces::Error; end
    class SecretMissing < Codespaces::GetPrebuildSecrets::Error; end

    LEGACY_PREBUILD_PAT_SECRET_KEY = "EXPERIMENTAL_CODESPACE_CACHE_TOKEN"
    PREBUILD_PAT_SECRET_KEY = "CODESPACES_PREBUILD_TOKEN"

    PREBUILD_PAT_SECRET_KEYS = [LEGACY_PREBUILD_PAT_SECRET_KEY, PREBUILD_PAT_SECRET_KEY]

    attr_accessor :repository, :pat_secret_required, :branch
    attr_reader :entry_point

    def initialize(repository:, pat_secret_required: false, branch: nil, entry_point: nil)
      @repository = repository
      @pat_secret_required = pat_secret_required
      @branch = branch
      @entry_point = entry_point
    end

    def perform
      secrets, filtered_secrets = get_secrets
      token = decrypted_pat_token(filtered_secrets)
      if pat_secret_required && token.nil?
        # mint a new repo-scoped token
        token, _ = ::Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repository, branch, entry_point: entry_point)
      end

      {
        secrets: secrets,
        github_token: token
      }
    end

    private

    def decrypted_pat_token(filtered_secrets)
      encrypted_pat_token = filtered_secrets.find { |s| PREBUILD_PAT_SECRET_KEY == s.name }
      unless encrypted_pat_token.present?
        encrypted_pat_token = filtered_secrets.find { |s| LEGACY_PREBUILD_PAT_SECRET_KEY == s.name }
        GitHub.dogstats.increment("codespaces.get_prebuild_secrets.decrypted_path_token.legacy_prebuild_pat", tags: [@repository.id]) if encrypted_pat_token
      end

      return nil unless encrypted_pat_token
      encrypted_pat_token.decrypt
    end

    def get_secrets
      secrets = []
      max_attempts = 3
      attempts = 0
      retry_backoff = 0.2

      begin
        attempts += 1
        secrets, filtered_secrets = ::Codespaces::Secret.for_prebuild(repository: repository)
      rescue Secrets::Error => e
        Codespaces::ErrorReporter.report(e, repository_id: repository.id)
        if attempts <= max_attempts
          sleep retry_backoff
          retry
        else
          GitHub.dogstats.increment("prebuild.secrets", tags: ["outcome:failure", "attempts:#{attempts}"])
          raise
        end
      end
      GitHub.dogstats.increment("prebuild.secrets", tags: ["outcome:success", "attempts:#{attempts}"])
      [secrets, filtered_secrets]
    end
  end
end
