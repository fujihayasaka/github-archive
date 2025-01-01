# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestDiff < Platform::Loader
      def self.load(pull_request, start_commit_oid:, end_commit_oid:, base_commit_oid:)
        self.for(pull_request).load({
          start_commit_oid: start_commit_oid,
          end_commit_oid: end_commit_oid,
          base_commit_oid: base_commit_oid,
        })
      end

      def initialize(pull_request)
        @pull_request = pull_request
      end

      def fetch(ranges)
        repository = @pull_request.compare_repository

        ranges.each_with_object({}) do |range, result|
          diff = GitHub::Diff.new(repository, range[:start_commit_oid], range[:end_commit_oid], {
            base_sha: range[:base_commit_oid],
          })

          diff.load_diff

          result[range] = diff if diff.available?
        end
      end
    end
  end
end
