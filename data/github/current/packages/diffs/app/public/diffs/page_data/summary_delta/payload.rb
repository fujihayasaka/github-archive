# typed: strict
# frozen_string_literal: true

module Diffs::PageData::SummaryDelta
  class Payload
    class SummaryDelta < T::Struct
      const :linesAdded, Integer
      const :linesDeleted, Integer
      const :path, String
      const :pathDigest, String
      const :status, Diffs::Entry::ChangeType
    end

    sig do
      params(summary_delta: GitRPC::Diff::Summary::Delta).returns(SummaryDelta)
    end
    def self.call(summary_delta)
      new.call(summary_delta)
    end

    sig do
      params(summary_delta: GitRPC::Diff::Summary::Delta).returns(SummaryDelta)
    end
    def call(summary_delta)
      SummaryDelta.new(
        linesAdded: summary_delta.additions || 0,
        linesDeleted: summary_delta.deletions || 0,
        path: summary_delta.path,
        pathDigest: Digest::SHA256.hexdigest(summary_delta.path),
        status: Diffs::Entry::ChangeType.deserialize(summary_delta.status_label&.upcase),
      )
    end
  end
end
