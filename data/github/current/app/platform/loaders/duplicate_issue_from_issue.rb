# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class DuplicateIssueFromIssue < Platform::Loader
      def self.load(duplicate_issue_id)
        self.for.load(duplicate_issue_id)
      end

      def fetch(duplicate_issue_ids)
        results = Hash.new { |hash, key| hash[key] = [] }
        ::DuplicateIssue.marked_as_duplicate.with_duplicate_issue(duplicate_issue_ids).each do |dupe|
          results[dupe.issue_id] << dupe
        end
        results
      end
    end
  end
end
