# typed: true
# frozen_string_literal: true

class Issue::Loader::DuplicateIssues < Issue::Loader::Base
  def initialize(context, canonical_and_issue_ids: [])
    @context = context
    @canonical_and_issue_ids = canonical_and_issue_ids
  end

  def self.load_for(context, canonical_and_issue_ids: [])
    super new(context, canonical_and_issue_ids: canonical_and_issue_ids)
  end

  def load
    return {} unless @canonical_and_issue_ids.any?

    ::DuplicateIssue.with_canonical_and_duplicates(@canonical_and_issue_ids).index_by do |dupe|
      [dupe.canonical_issue_id, dupe.issue_id]
    end
  end
end
