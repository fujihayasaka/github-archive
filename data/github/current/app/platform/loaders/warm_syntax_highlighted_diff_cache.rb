# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class WarmSyntaxHighlightedDiffCache < Platform::Loader
      def self.load(repository, pull_request, diff_entry)
        self.for(repository, pull_request).load(diff_entry)
      end

      def initialize(repository, pull_request)
        @repository = repository
        @pull_request = pull_request
      end

      def load(key)
        # SyntaxHighlightedDiff#highlight! ends up checking
        # the `Configurable` property repository.git_lfs_enabled?.
        # Anything calling into `Configurable` properties from an async context
        # needs to preload async_configuration_owners
        repository.async_configuration_owners.then { super(key) }
      end

      def fetch(diff_entries)
        diff = ::SyntaxHighlightedDiff.new(repository)
        diff.highlight!(diff_entries, attributes_commit_oid: pull_request&.head_sha)

        {} # we just fill the cache
      end

      private

      attr_reader :repository, :pull_request
    end
  end
end
