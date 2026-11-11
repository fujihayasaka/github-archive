# frozen_string_literal: true

require "dependabot/octokit_middleware/access_token_authentication"

module GitHub
  class RESTClient < ::Octokit::Client
    module AccountAuthentication
      def self.regenerate_token(account:, repo_ids:, permissions:)
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

      def using_account_auth(account:, repo_ids: nil, permissions: nil, max_retries: 1)
        access_token = GitHubHelpers.access_token_for(account:, repo_ids:, permissions:)
        regenerate_callback = -> { AccountAuthentication.regenerate_token(account:, repo_ids:, permissions:) }

        if middleware.handlers.include?(Dependabot::OctokitMiddleware::AccessTokenAuthentication)
          middleware.swap(Dependabot::OctokitMiddleware::AccessTokenAuthentication,
                          Dependabot::OctokitMiddleware::AccessTokenAuthentication,
                          token: access_token,
                          tenant: account.tenant,
                          regenerate_token_callback: regenerate_callback,
                          max_retries: max_retries)
        else
          middleware.insert(0, Dependabot::OctokitMiddleware::AccessTokenAuthentication,
                            token: access_token,
                            tenant: account.tenant,
                            regenerate_token_callback: regenerate_callback,
                            max_retries: max_retries)
        end

        # The agent needs to be reset after changing the middleware stack
        @agent = nil

        self
      end
    end
  end
end
