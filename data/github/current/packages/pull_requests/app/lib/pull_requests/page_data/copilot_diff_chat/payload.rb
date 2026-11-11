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
      const :commitMessage, T.nilable(String)
      const :linesAdded, T.nilable(Integer)
      const :linesDeleted, T.nilable(Integer)
      const :pullRequestUrl, T.nilable(String)
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
      include_context = data.include_context

      # Build a combined commit message from all PR commits when context is enabled
      commit_message = if include_context
        build_commit_message(data.pull_request)
      end

      pr_url = if include_context
        data.pull_request.url
      end

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
          commitMessage: include_context ? commit_message : nil,
          linesAdded: include_context ? entry.additions : nil,
          linesDeleted: include_context ? entry.deletions : nil,
          pullRequestUrl: include_context ? pr_url : nil,
        )

        DiffEntry.new(
          reference: diff_entry_reference,
          path: head_file&.path || base_file&.path || ""
        )
      end
    end

    private

    sig { params(pull_request: PullRequest).returns(T.nilable(String)) }
    def build_commit_message(pull_request)
      commits = pull_request.historical_comparison.commits.compact.first(10)
      return nil if commits.empty?

      messages = commits.filter_map { |c| c.message.presence }
      return nil if messages.empty?

      combined = messages.join("\n\n")
      combined.length > 75 ? combined[0, 75] + "…" : combined
    end
  end
end
