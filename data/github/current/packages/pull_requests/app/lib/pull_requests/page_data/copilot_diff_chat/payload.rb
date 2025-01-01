# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CopilotDiffChat
  class Payload
    class FileReference < T::Struct
      const :type, String
      const :url, String
      const :path, String
      const :repoID, Numeric
      const :repoOwner, String
      const :repoName, String
      const :ref, String
      const :commitOID, String
    end

    class DiffEntryReference < T::Struct
      const :type, String
      const :id, String
      const :url, String
      const :baseFile, T.nilable(FileReference)
      const :headFile, T.nilable(FileReference)
      const :baseBranchRef, T.nilable(String)
    end

    class DiffEntry < T::Struct
      const :reference, DiffEntryReference
      const :path, String
    end

    sig { params(data: PullRequests::PageData::CopilotDiffChat::Loader::CopilotDiffChat).returns(T::Array[DiffEntry]) }
    def self.call(data)
      new.call(data)
    end

    sig { params(data: PullRequests::PageData::CopilotDiffChat::Loader::CopilotDiffChat).returns(T::Array[DiffEntry]) }
    def call(data)
      base_repository = data.base_repository
      head_repository = data.head_repository

      data.entries.map do |entry|

        path_digest = Digest::SHA256.hexdigest(entry.path)

        if entry.a_path && base_repository
          base_file = FileReference.new(
            type: "file",
            url:  base_repository.name_with_display_owner + "/raw/" + entry.a_sha + "/" + entry.a_path,
            path: entry.a_path,
            repoID: base_repository.id,
            repoOwner: T.must(data.base_owner_login),
            repoName: base_repository.name,
            ref: entry.a_sha,
            commitOID: entry.a_sha,
          )
        end

        if entry.b_path && head_repository
          head_file = FileReference.new(
            type: "file",
            url: head_repository.name_with_display_owner + "/raw/" + entry.b_sha + "/" + entry.b_path,
            path: entry.b_path,
            repoID: head_repository.id,
            repoOwner: T.must(data.head_owner_login),
            repoName: head_repository.name,
            ref: entry.b_sha,
            commitOID: entry.b_sha,
          )
        end

        diff_entry_reference = DiffEntryReference.new(
          id: "diff-#{path_digest}",
          url: base_file&.url || head_file&.url || "",
          type: "file-diff",
          baseFile: base_file,
          headFile: head_file,
          baseBranchRef: data.base_branch_ref,
        )

        DiffEntry.new(
          reference: diff_entry_reference,
          path: head_file&.path || base_file&.path || ""
        )
      end
    end
  end
end
