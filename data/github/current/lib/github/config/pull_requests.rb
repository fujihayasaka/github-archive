# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module PullRequests

      DEFAULT_DUPLICATE_HEAD_SHA_LIMIT = 100

      # Public: Limit for the number of pull requests that can be created with
      # the same head_sha in a single repository.
      #
      # This value can be overridden as an emergency escape hatch for Enterprise customers.
      #
      # Returns an Integer.
      def duplicate_head_sha_limit
        @duplicate_head_sha_limit || DEFAULT_DUPLICATE_HEAD_SHA_LIMIT
      end
      attr_writer :duplicate_head_sha_limit
    end
  end

  extend Config::PullRequests
end
