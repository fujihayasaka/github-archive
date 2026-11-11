# frozen_string_literal: true

require "octokit"

require_relative "rest_client/account_authentication"
require_relative "rest_client/etag_cache"
require_relative "rest_client/pagination"
require_relative "rest_client/retries"

module GitHub
  class RESTClient < ::Octokit::Client
    DEFAULT_CLIENT_ARGS = {
      connection_options: { request: { open_timeout: 2, timeout: 10 } },
      user_agent: "github/dependabot-api (#{::Octokit::Default.user_agent})",
    }.freeze

    class << self
      def default_client_args
        DEFAULT_CLIENT_ARGS.merge(api_endpoint: Dependabot::Application.target_github_internal_api_endpoint)
      end
    end

    prepend GitHub::RESTClient::AccountAuthentication
    prepend GitHub::RESTClient::EtagCache
    prepend GitHub::RESTClient::Pagination
    prepend GitHub::RESTClient::Retries

    def initialize(options = {})
      options_with_default_args = self.class.default_client_args.merge(options)
      max_retries = options_with_default_args.delete(:max_retries) || 2

      super(options_with_default_args)

      # don't mutate the global octokit middleware stack with any of the
      # custom extensions/middleware in the prepended modules
      self.middleware = middleware.dup if middleware.equal?(Octokit.middleware)

      # retry common failures by default
      using_retries(max: max_retries)
    end
  end
end
