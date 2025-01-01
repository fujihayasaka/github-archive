# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class Payload
    class Summary < T::Struct
      const :changeType, Diffs::Entry::ChangeType
      const :isManifestFile, T::Boolean
      const :isVendored, T::Boolean
      const :path, String
      const :pathDigest, String
      const :linesAdded, Integer
      const :linesChanged, Integer
      const :linesDeleted, Integer
    end

    class Payload < T::Struct
      const :summaries, T::Array[Summary]
    end

    sig do
      params(summary_data: PullRequests::PageData::Diffs::Summary::Loader::Data).returns(Payload)
    end
    def self.call(summary_data)
      new.call(summary_data)
    end

    sig do
      params(summary_data: PullRequests::PageData::Diffs::Summary::Loader::Data).returns(Payload)
    end
    def call(summary_data)
      Payload.new(
        summaries: summary_data.summaries.map do |diff_summary|
          Summary.new(
            changeType: diff_summary.change_type,
            isManifestFile: diff_summary.is_manifest_file,
            isVendored: diff_summary.vendored?,
            path: diff_summary.path,
            pathDigest: Digest::SHA256.hexdigest(diff_summary.path),
            linesAdded: diff_summary.lines_added,
            linesChanged: diff_summary.lines_changed,
            linesDeleted: diff_summary.lines_deleted
          )
        end
      )
    end
  end
end
