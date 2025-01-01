# typed: true
# frozen_string_literal: true

module DependencyGraph
  module BaseTwirpClientHandler
    # This method is meant to wrap invocations of our Twirp clients, usually to do error handling / logging.
    # We want explicit error logging in this method for a couple reasons, the most important is that we need to
    # make sure that these calls are tagged with the error_payload before they keep failing "up" past this execution boundary.
    # This method also decides when to log to Failbot: for things that are deemed "client" errors (400-series) we intentionally
    # do not log to Failbot.
    #
    # error_payload - The hash that should be logged whenever an error occurs. The caller can have additional context as well
    #                 as an identifying key that we can use to search splunk.
    # should_coalesce_error - If true, we should coalesce errors into well formed result objects instead of reraising. If
    #                         false, we should let the errors follow their normal course (after reporting when appropriate).
    # block - The ruby block to execute this handler "around". The author couldn't originally figure out how to elegantly collapse
    #         the calling method (which takes &block) into this method, so this is just taking a normal block as input.
    def self.client_handler(error_payload, should_coalesce_error, block)
      error_payload = error_payload.merge(app: "github-dependency-graph")
      begin
        block.call
      rescue Faraday::TimeoutError => error
        Failbot.report(error, error_payload)
        raise error unless should_coalesce_error
        coalesce_error(500, "Request not processed in time. Please try again or reach out if this problem persists.")
      rescue DependencyGraph::BaseTwirpClient::NotFoundError => error
        raise error unless should_coalesce_error
        coalesce_error(404, "Resource was not found")
      rescue DependencyGraph::BaseTwirpClient::BadRequestError => error
        raise error unless should_coalesce_error
        coalesce_error(400, error.to_s)
      rescue DependencyGraph::BaseTwirpClient::CircuitBrokenError => error
        Failbot.report(error, error_payload)
        raise error unless should_coalesce_error
        coalesce_error(500, "Too many failed requests have occurred in a short period of time.")
      rescue DependencyGraph::BaseTwirpClient::MalformedError => error
        raise error unless should_coalesce_error
        # NOTE: Twirp currently does not support returning 422 responses, or we would do that in ds-api instead of
        # returning a 400 for validation errors. But GH typically returns 422 for validation errors, so we'll do that
        # here.
        coalesce_error(422, error.to_s)
      rescue DependencyGraph::BaseTwirpClient::Error => error
        Failbot.report(error, error_payload)
        raise error unless should_coalesce_error
        coalesce_error(500, "An unexpected error occurred while processing request. Please try again later or reach out if this problem persists.")
      end
    end

    def self.coalesce_error(status_code, error_string)
      {
        status_code: status_code,
        response: nil,
        errors: [error_string]
      }
    end
  end
end
