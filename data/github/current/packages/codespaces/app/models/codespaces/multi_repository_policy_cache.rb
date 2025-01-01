# typed: true
# frozen_string_literal: true

# Avoids N+1 queries to authzd when resolving RepositoryPolicies across multiple codespaces spanning multiple
# repositories. This is done by building up a cache/hash of codespace=>policy and utilizing Promise.all(policies).sync
# to batch those requests together. When fetching a policy for a codespace we will return the appropriate batch-resolved
# policy for it based on its owner, repository, and pull request (if any).
module Codespaces
  class MultiRepositoryPolicyCache
    include GitHub::ResilienceMixin

    def initialize(codespaces)
      @codespaces = Array(codespaces)
    end

    def get(codespace)
      policy_cache[cache_key(codespace)].sync
    end

    private

    def policy_cache
      return @policy_cache if defined?(@policy_cache)

      # Set up our repository policies for all of the codespaces
      @policy_cache = @codespaces.each_with_object({}) do |codespace, memo|
        memo[cache_key(codespace)] = repository_policy(codespace)
      end
      # Resolve them all to batch any necessary requests to authzd
      Promise.all(@policy_cache.values).sync
      @policy_cache
    end

    def safe_pr(codespace)
      with_database_error_fallback(fallback: nil) { codespace.pull_request }
    end

    def cache_key(codespace)
      [codespace.owner, codespace.repository, safe_pr(codespace)]
    end

    def repository_policy(codespace)
      Codespaces::RepositoryPolicy.async_with_prefill(codespace.owner, codespace.repository, pull_request: safe_pr(codespace))
    end
  end
end
