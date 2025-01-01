# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::FileTree
  class Payload
    include DiffHelper

    # Used in commit range selector only
    class Commit < T::Struct
      const :actorLogin, String
      const :createdAt, String
      const :messageHeadline, String
      const :oid, String
      const :shortOid, String
    end

    class Diff < T::Struct
      const :changeType, Diffs::Entry::ChangeType
      const :isCodeowner, T::Boolean
      const :isManifestFile, T::Boolean
      const :isVendored, T::Boolean
      const :markedAsViewed, T::Boolean
      const :path, String
      const :pathDigest, String
      const :highestAnnotationLevel, T.nilable(PullRequests::PageData::Annotations::Payload::AnnotationLevel)
      const :totalCommentsCount, T.nilable(Integer)
    end

    class Payload < T::Struct
      const :baseRefOid, String
      const :commits, T::Array[Commit]
      const :diffs, T::Array[Diff]
      const :lastReviewOid, T.nilable(String)
      const :ownerLogin, String
      const :pathName, String
      const :pullRequestId, String
      const :pullRequestNumber, Numeric
      const :repositoryName, String
      # TODO unselectedFileExtensions, used in file filter
    end

    sig do
      params(file_tree_data: PullRequests::PageData::Files::FileTree::Loader::Data).returns(Payload)
    end
    def self.call(file_tree_data)
      new.call(file_tree_data)
    end

    sig do
      params(file_tree_data: PullRequests::PageData::Files::FileTree::Loader::Data).returns(Payload)
    end
    def call(file_tree_data)
      annotations = PullRequests::PageData::Annotations::Payload.annotations_highest_level(file_tree_data.annotations)

      Payload.new(
        baseRefOid: file_tree_data.base_ref_oid,
        commits: file_tree_data.commits.map do |commit|
          Commit.new(
            actorLogin: commit.user_display_login,
            createdAt: commit.created_at.to_s,
            messageHeadline: commit.short_message_text,
            oid: commit.oid,
            shortOid: commit.abbreviated_oid
          )
        end,
        diffs: file_tree_data.diffs.map do |diff|
          Diff.new(
            changeType: Diffs::Entry::ChangeType.deserialize(diff.diff_delta.status_label&.upcase),
            isCodeowner: diff.is_codeowner,
            isManifestFile: DependencyManifestFile.recognized_path?(path: diff.diff_delta.path),
            isVendored: diff.tree_entry.vendored?,
            markedAsViewed: file_tree_data.viewed_files.reviewed?(diff.diff_delta.path),
            path: diff.diff_delta.path,
            pathDigest: Digest::SHA256.hexdigest(diff.diff_delta.path),
            highestAnnotationLevel: annotations[diff.diff_delta.path].nil? ? nil : PullRequests::PageData::Annotations::Payload::AnnotationLevel.deserialize(annotations[diff.diff_delta.path].to_s.upcase),
            totalCommentsCount: file_tree_data.thread_previews[diff.diff_delta.path],
          )
        end,
        lastReviewOid: file_tree_data.last_review_oid,
        ownerLogin: file_tree_data.repository.owner_display_login,
        pathName: T.must(file_tree_data.pull_request.permalink(include_host: false)),
        pullRequestId: file_tree_data.pull_request.global_relay_id,
        pullRequestNumber: file_tree_data.pull_request.number,
        repositoryName: file_tree_data.repository.name
      )
    end
  end
end
