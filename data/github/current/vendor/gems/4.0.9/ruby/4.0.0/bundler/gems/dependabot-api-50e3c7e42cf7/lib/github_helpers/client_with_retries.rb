# frozen_string_literal: true

require "dependabot/octokit_middleware/tenancy_headers"

module GitHubHelpers
  class ClientWithRetries
    def initialize(etag_caching: false, max_retries: 1, account: nil,
                   repo_ids: nil, permissions: nil, **args)
      raise ArgumentError, "installation_id is no longer supported" if args[:installation_id].present?

      @account = account
      @repo_ids = repo_ids
      @permissions = permissions
      @max_retries = max_retries || 1

      if etag_caching
        args[:middleware] = Octokit.middleware.dup.tap do |stack|
          stack.insert(0, Faraday::EtagCache, cache: Rails.cache)
        end
      end

      args = default_client_args.merge(args)

      if account
        token = GitHubHelpers.access_token_for(account: account, repo_ids: repo_ids, permissions: permissions)
        args[:access_token] = token

        args[:middleware] = Octokit.middleware.dup.tap do |stack|
          stack.insert(0, Dependabot::OctokitMiddleware::TenancyHeaders, tenant: account.tenant)
        end
      end

      @client = GitHubHelpers.octokit_client_for(args)
    end

    # rubocop:disable Metrics/PerceivedComplexity
    def method_missing(method_name, *args, &block)
      GitHubHelpers.with_connection_failure_retrying(max_retries) do
        if @client.respond_to?(method_name)
          mutatable_args = args.map(&:dup)
          @client.public_send(method_name, *mutatable_args, &block)
        else
          super
        end
      end
    rescue Octokit::Unauthorized => e
      credentials_retry_attempt ||= 0
      credentials_retry_attempt += 1
      raise unless account
      raise unless e.message.include?("Bad credentials")
      raise unless credentials_retry_attempt <= 1
      raise e unless (token = regenerate_token)

      @client.access_token = token
      retry
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def respond_to_missing?(method_name, include_private = false)
      @client.respond_to?(method_name) || super
    end

    private

    attr_reader :account, :repo_ids, :permissions, :max_retries

    def regenerate_token
      GitHubHelpers.delete_cached_access_token_for(
        account: account,
        repo_ids: repo_ids,
        permissions: permissions
      )
      GitHubHelpers.access_token_for(
        account: account,
        repo_ids: repo_ids,
        permissions: permissions
      )
    end

    def default_client_args
      { api_endpoint: target_github_api_endpoint }
    end

    def target_github_api_endpoint
      Dependabot::Application.target_github_internal_api_endpoint
    end
  end
end
