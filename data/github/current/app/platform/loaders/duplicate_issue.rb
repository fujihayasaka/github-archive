# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class DuplicateIssue < Platform::Loader
      def self.load(canonical_issue_id, duplicate_issue_id)
        self.for.load([canonical_issue_id, duplicate_issue_id])
      end

      def fetch(canonical_and_duplicate_issue_ids)
        ::DuplicateIssue.with_canonical_and_duplicates(canonical_and_duplicate_issue_ids).index_by do |dupe|
          [dupe.canonical_issue_id, dupe.issue_id]
        end
      end
    end
  end
end
