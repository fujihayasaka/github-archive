# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  class Loader
    include GitHub::ResilienceMixin

    class Data < T::Struct
      const :diff_contents, PullRequests::PageData::Diffs::Contents::Loader::Data
      const :toolbar, PullRequests::PageData::Files::Toolbar::Loader::Data
      const :file_tree, PullRequests::PageData::Files::FileTree::Loader::Data
      const :header, T::Hash[String, T.untyped]
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        ignore_whitespace: T::Boolean,
        pull_request: ::PullRequest,
        timeout: T.any(Integer, Float),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        current_user: T.nilable(User),
      ).returns(Data)
    end
    def self.load(comparison:, ignore_whitespace:, pull_request:, timeout:, cap_filter:, user_session:, current_user: nil)
      new(comparison:, ignore_whitespace:, pull_request:, timeout:, cap_filter:, user_session:, current_user:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        ignore_whitespace: T::Boolean,
        pull_request: ::PullRequest,
        timeout: T.any(Integer, Float),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        current_user: T.nilable(User),
      ).void
    end
    def initialize(comparison:, ignore_whitespace:, pull_request:, timeout:, cap_filter:, user_session:, current_user:)
      @cap_filter = cap_filter
      @comparison = comparison
      @current_user = current_user
      @ignore_whitespace = ignore_whitespace
      @pull_request = pull_request
      @timeout = timeout
      @user_session = user_session
    end

    sig { returns(Data) }
    def load
      header_data = PullRequests::PageData::HeaderPayload.build(
        current_user: @current_user,
        pull_request: @pull_request,
      )

      file_tree_data = PullRequests::PageData::Files::FileTree::Loader.load(
        comparison: @comparison,
        current_user: @current_user,
        pull_request: @pull_request,
        cap_filter: @cap_filter,
        user_session: @user_session,
        end_commit_oid: @comparison.end_commit.oid,
      )

      diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
        diff: @comparison.diff,
        ignore_whitespace: @ignore_whitespace,
        timeout: @timeout,
        top_only: true,
        repository: @pull_request.head_repository,
        viewed_files: file_tree_data.viewed_files,
      )

      toolbar_data = PullRequests::PageData::Files::Toolbar::Loader.load(
        cap_filter: @cap_filter,
        comparison: @comparison,
        current_user: @current_user,
        end_commit_oid: @comparison.end_commit.oid,
        pull_request: @pull_request,
        user_session: @user_session,
      )

      Data.new(
        toolbar: toolbar_data,
        header: header_data,
        file_tree: file_tree_data,
        diff_contents: diff_contents_data,
      )
    end
  end
end
