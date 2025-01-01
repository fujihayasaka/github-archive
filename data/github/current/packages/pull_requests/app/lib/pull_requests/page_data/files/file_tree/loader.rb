# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::FileTree
  class Loader
    include GitHub::ResilienceMixin
    include GitHub::Memoizer

    class FileTreeDiff < T::Struct
      const :diff_delta, GitRPC::Diff::Delta
      const :is_codeowner, T::Boolean
      const :tree_entry, TreeEntry
    end

    class Data < T::Struct
      const :base_ref_oid, String
      const :codeowners, T.nilable(Repository::Codeowners)
      const :commits, T::Array[Commit]
      const :diffs, T::Array[FileTreeDiff]
      const :thread_previews, T::Hash[String, Integer]
      const :annotations, T::Array[PullRequests::PageData::Annotations::Loader::AnnotationLevelWithPath]
      const :last_review_oid, T.nilable(String)
      const :pull_request, ::PullRequest
      const :repository, Repository
      const :viewed_files, PullRequestUserReviews
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        end_commit_oid: String,
        current_user: T.nilable(User),
      ).returns(Data)
    end
    def self.load(comparison:, pull_request:, cap_filter:, user_session:, end_commit_oid:, current_user: nil)
      new(comparison:, pull_request:, cap_filter:, user_session:, end_commit_oid:, current_user:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        end_commit_oid: String,
        current_user: T.nilable(User),
      ).void
    end
    def initialize(comparison:, pull_request:, cap_filter:, user_session:, end_commit_oid:, current_user:)
      @comparison = comparison
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
      @end_commit_oid = end_commit_oid
      @user_session = user_session
    end

    sig { returns(Data) }
    def load
      diff_summaries = PullRequests::PageData::Diffs::Summary::Loader.load(
        diff: @comparison.diff,
        repository: @pull_request.repository,
      ).summaries

      diffs = diff_summaries.map do |diff_summary|
        FileTreeDiff.new(
          diff_delta: diff_summary.diff_delta,
          is_codeowner: codeowners&.owned_by?(owner: @current_user, path: diff_summary.diff_delta.path),
          tree_entry: diff_summary.tree_entry,
        )
      end

      Data.new(
        base_ref_oid: @comparison.start_commit.oid,
        commits: @pull_request.changed_commits,
        diffs: diffs,
        thread_previews: PullRequests::PageData::ThreadPreviews::Loader.load_counts_by_path(
          cap_filter: @cap_filter,
          current_user: @current_user,
          pull_request: @pull_request
        ),
        annotations: PullRequests::PageData::Annotations::Loader.load_annotation_levels_with_path(
          current_user: @current_user,
          pull_request: @pull_request,
          user_session: @user_session,
          end_commit_oid: @end_commit_oid
        ),
        last_review_oid: last_review_oid,
        pull_request: @pull_request,
        repository: T.must(@pull_request.repository),
        viewed_files: PullRequestUserReviews.new(@pull_request, @current_user),
      )
    end

    private

    sig { returns(T.nilable(Repository::Codeowners)) }
    memoize def codeowners
      @pull_request.codeowners
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing => e
      Failbot.report(e)
      GitHub.logger.error("Failed to load codeowners for pull request", e)
      nil
    end

    sig { returns(T.nilable(String)) }
    def last_review_oid
      return nil unless @current_user.present?

      @pull_request.latest_non_pending_review_for(@current_user)&.head_sha
    end

    sig do
      params(
        file: GitRPC::Diff::Delta::TreeNode,
        repository: T.nilable(Repository)
      ).returns(TreeEntry)
    end
    def diff_delta_file_blob(file, repository = nil)
      TreeEntry.new(repository, {
        "oid" => file.oid,
        "path" => file.path,
        "mode" => file.mode,
        "type" => "blob",
      })
    end

    sig do
      params(
        diff: GitRPC::Diff::Delta,
        repository: T.nilable(Repository)
      ).returns(TreeEntry)
    end
    def diff_delta_blob(diff, repository = nil)
      if diff.deleted?
        diff_delta_file_blob(diff.old_file, repository)
      else
        diff_delta_file_blob(diff.new_file, repository)
      end
    end
  end
end
