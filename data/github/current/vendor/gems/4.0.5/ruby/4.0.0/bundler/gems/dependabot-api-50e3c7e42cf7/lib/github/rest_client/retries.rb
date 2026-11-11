# frozen_string_literal: true

require "github_helpers"

module GitHub
  class RESTClient < ::Octokit::Client
    module Retries
      DEFAULT_EXCEPTIONS = [
        # Exceptions that Faraday::Retry::Middleware normally captures
        *Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS,
        # Retry known connection failurs,
        *GitHubHelpers::CONNECTION_FAILURE_ERRORS,
        Zlib::BufError,
        # The retry middleware added by octokit includes ServerError, including here for parity.
        # https://github.com/octokit/octokit.rb/blob/687944a823cf5b52cf10050acecf78785fadb9ff/lib/octokit/default.rb#L40
        Octokit::ServerError,
      ].freeze

      def using_retries(**retry_options)
        retry_options[:exceptions] ||= DEFAULT_EXCEPTIONS
        if middleware.handlers.include?(Faraday::Retry::Middleware)
          middleware.swap(Faraday::Retry::Middleware, Faraday::Retry::Middleware, **retry_options)
        else
          middleware.insert(0, Faraday::Retry::Middleware, **retry_options)
        end

        # The agent needs to be reset after changing the middleware stack
        @agent = nil

        self
      end
    end
  end
end
