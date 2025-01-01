# typed: strict
# frozen_string_literal: true

module Diffs::PageData::Submodule
  class Payload
    class Payload < T::Struct
      const :basePath, String
      const :changedFiles, Integer
      const :contentsUrl, T.nilable(String)
      const :newCommitOid, T.nilable(String)
      const :oldCommitOid, T.nilable(String)
      const :status, Diffs::Entry::ChangeType
      const :submoduleUrl, T.nilable(String)
      const :summary, T::Array[Diffs::PageData::SummaryDelta::Payload::SummaryDelta]

      # This is used in New Commit Details to properly serialize the hash payloads.
      # Once that page is converted to loaders/payloads properly, this can go away.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          basePath: self.basePath,
          changedFiles: self.changedFiles,
          submoduleUrl: self.submoduleUrl,
          newCommitOid: self.newCommitOid,
          oldCommitOid: self.oldCommitOid,
          status: self.status,
          contentsUrl: self.contentsUrl,
          summary: self.summary.map do |summary_delta|
            {
              linesAdded: summary_delta.linesAdded,
              linesDeleted: summary_delta.linesDeleted,
              path: summary_delta.path,
              pathDigest: summary_delta.pathDigest,
              status: summary_delta.status,
            }
          end
        }
      end
    end

    sig do
      params(loader_data: Diffs::PageData::Submodule::Loader::Data).returns(Payload)
    end
    def self.call(loader_data)
      new.call(loader_data)
    end

    sig do
      params(loader_data: Diffs::PageData::Submodule::Loader::Data).returns(Payload)
    end
    def call(loader_data)
      Payload.new(
        basePath: loader_data.base_path,
        changedFiles: loader_data.changed_files || 0,
        contentsUrl: loader_data.contents_url,
        newCommitOid: loader_data.diff_entry.b_blob,
        oldCommitOid: loader_data.diff_entry.a_blob,
        status: Diffs::Entry::ChangeType.deserialize(loader_data.diff_entry.status_label&.upcase),
        submoduleUrl: loader_data.path_link,
        summary: loader_data.summary_deltas.map do |summary_delta|
          Diffs::PageData::SummaryDelta::Payload.call(summary_delta)
        end,
      )
    end
  end
end
