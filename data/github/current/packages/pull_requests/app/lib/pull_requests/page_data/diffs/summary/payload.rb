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
            changeType: Diffs::Entry::ChangeType.deserialize(diff_summary.diff_delta.status_label&.upcase),
            isManifestFile: DependencyManifestFile.recognized_path?(path: diff_summary.diff_delta.path),
            isVendored: diff_summary.tree_entry.vendored?,
            path: diff_summary.diff_delta.path,
            pathDigest: Digest::SHA256.hexdigest(diff_summary.diff_delta.path),
          )
        end
      )
    end
  end
end
