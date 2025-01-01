# typed: true
# frozen_string_literal: true

require "github"
require "presto-client"

module GitHub
  module Config
    # Mixin for the GitHub module that gives access to the presto config
    # and also a memoized GitHub::Presto::Client singleton for presto access.
    module Presto
      attr_writer :presto

      # Public: Return the Presto::Client instance
      def presto
        return @presto if defined?(@presto)
        self.presto = default_presto_client
      end

      private

      def presto_access_allowed?
        Rails.env.production? || ENV["ALLOW_PRESTO"]
      end

      # Private: Create and return the default presto client
      def default_presto_client
        return NoopPrestoClient.new unless presto_access_allowed?

        ::Presto::Client.new(
          server: "presto-coordinator.service.github.net:8080",
          user: "dotcom",
        )
      end

      # A no-op presto client to return results in dev and test.
      class NoopPrestoClient
        def run(*args)
          [[], []]
        end

        def run_with_names(*args)
          []
        end
      end
    end
  end

  extend Config::Presto
end
