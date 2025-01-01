# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  class Loader
    include GitHub::ResilienceMixin

    FileFilterInputs = T.type_alias do
      {
        selected_file_extensions: T.nilable(T::Array[String]),
        show_deleted_files: T::Boolean,
        show_only_manifest_files: T::Boolean,
        show_only_owned_files: T::Boolean,
        show_vendored_files: T::Boolean,
        show_viewed_files: T::Boolean,
      }
    end

    FILE_FILTER_DEFAULTS = T.let({
      selected_file_extensions: nil,
      show_deleted_files: true,
      show_only_manifest_files: false,
      show_only_owned_files: false,
      show_vendored_files: true,
      show_viewed_files: true,
    }, FileFilterInputs)

    class PullRequestThreadData < T::Struct
      const :id, Numeric
      const :subject_type, String
      const :is_resolved, T::Boolean
      const :viewer_can_reply, T::Boolean
      const :thread_comments, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
      const :review_comments_limit, Integer
      const :review_comments_limit_exceeded, T::Boolean
    end

    class FileFilterData < T::Struct
      const :file_extensions_with_counts, T::Hash[String, Numeric]
      const :show_deleted_files, T::Boolean
      const :show_only_manifest_files, T::Boolean
      const :show_only_owned_files, T::Boolean
      const :show_vendored_files, T::Boolean
      const :show_viewed_files, T::Boolean
      const :unselected_file_extensions, T::Array[String]
    end

    class UserData < T::Struct
      const :can_comment, T::Boolean
      const :tab_size, T.nilable(Integer)
    end

    class Data < T::Struct
      const :diff_contents, PullRequests::PageData::Diffs::Contents::Loader::Data
      const :toolbar, PullRequests::PageData::Files::Toolbar::Loader::Data
      const :file_filter, FileFilterData
      const :file_tree, PullRequests::PageData::Files::FileTree::Loader::Data
      const :header, T::Hash[String, T.untyped]
      const :codeowners, T.nilable(PullRequests::PageData::Codeowners::Loader::Data)
      const :threads, T::Array[PullRequestThreadData]
      const :user, UserData
      const :limit_config, PullRequests::PageData::Files::PageLimitConfig
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        ignore_whitespace: T::Boolean,
        pull_request: ::PullRequest,
        timeout: T.any(Integer, Float),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        highlighting_strategy: T.nilable(PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy),
        current_user: T.nilable(User),
        file_filter: T.nilable(FileFilterInputs),
        include_codeowners: T::Boolean,
      ).returns(Data)
    end
    def self.load(
      comparison:,
      ignore_whitespace:,
      pull_request:,
      timeout:,
      cap_filter:,
      user_session:,
      limit_config:,
      highlighting_strategy: PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy::ServerGenerated,
      current_user: nil,
      file_filter: nil,
      include_codeowners: false
    )
      new(comparison:, ignore_whitespace:, pull_request:, timeout:, cap_filter:, highlighting_strategy:, user_session:, limit_config:, current_user:, file_filter:, include_codeowners:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        file_filter: T.nilable(FileFilterInputs),
        ignore_whitespace: T::Boolean,
        pull_request: ::PullRequest,
        timeout: T.any(Integer, Float),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        highlighting_strategy: T.nilable(PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        current_user: T.nilable(User),
        include_codeowners: T::Boolean,
      ).void
    end
    def initialize(
      comparison:,
      file_filter:,
      ignore_whitespace:,
      pull_request:,
      timeout:,
      cap_filter:,
      user_session:,
      highlighting_strategy:,
      limit_config:,
      current_user:,
      include_codeowners:
    )
      @cap_filter = cap_filter
      @comparison = comparison
      @current_user = current_user
      @file_filter = T.let(file_filter || FILE_FILTER_DEFAULTS, FileFilterInputs)
      @ignore_whitespace = ignore_whitespace
      @pull_request = pull_request
      @timeout = timeout
      @highlighting_strategy = highlighting_strategy
      @user_session = user_session
      @limit_config = limit_config
      @include_codeowners = include_codeowners
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
        limit_config: @limit_config,
        include_codeowners: @include_codeowners,
      )

      diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
        current_user: @current_user,
        # Duplicate diff because loading thread previews interferes with the limits here
        diff: @comparison.diff.dup,
        ignore_whitespace: @ignore_whitespace,
        timeout: @timeout,
        highlighting_strategy: @highlighting_strategy,
        top_only: true,
        repository: @pull_request.head_repository,
        viewed_files: file_tree_data.viewed_files,
        limit_config: @limit_config,
      )

      toolbar_data = PullRequests::PageData::Files::Toolbar::Loader.load(
        cap_filter: @cap_filter,
        comparison: @comparison,
        current_user: @current_user,
        end_commit_oid: @comparison.end_commit.oid,
        pull_request: @pull_request,
        user_session: @user_session,
        limit_config: @limit_config,
        paths: file_tree_data.diffs.map(&:path),
      )

      file_extensions_with_counts = file_types_with_counts(@comparison.diff)
      diff_file_types = file_extensions_with_counts.keys
      selected_file_extensions = @file_filter[:selected_file_extensions] || diff_file_types

      file_filter_data = FileFilterData.new(
        file_extensions_with_counts: file_extensions_with_counts,
        show_deleted_files: @file_filter[:show_deleted_files],
        show_only_manifest_files: @file_filter[:show_only_manifest_files],
        show_only_owned_files: @file_filter[:show_only_owned_files],
        show_vendored_files: @file_filter[:show_vendored_files],
        show_viewed_files: @file_filter[:show_viewed_files],
        unselected_file_extensions: diff_file_types - selected_file_extensions,
      )

      threads = @limit_config.apply_page_limit(
        PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads
      ) do |limit|
        @pull_request.review_threads.visible_to(@current_user).limit(limit)
      end

      thread_promises = threads.map do |thread|
        Promise.all([
          thread_comments_promise(thread:),
          thread.async_viewer_can_reply?(@current_user),
        ]).then do |thread_comments_result, viewer_can_reply|
          thread_comments = thread_comments_result.review_comments
          thread_comments_limit_exceeded = thread_comments_result.review_comments_limit_exceeded

          PullRequestThreadData.new(
            id: thread.id,
            is_resolved: thread.resolved?,
            viewer_can_reply:,
            thread_comments:,
            subject_type: thread.subject_type,
            review_comments_limit_exceeded: thread_comments_limit_exceeded,
            review_comments_limit: @limit_config.review_comments_limit,
          )
        end
      end

      thread_data = Promise.all(thread_promises).sync

      user_data = UserData.new(
        can_comment: @current_user ? @pull_request.issue&.can_comment?(@current_user) : false,
        tab_size: @current_user&.settings&.get(:tab_size),
      )

      Data.new(
        toolbar: toolbar_data,
        header: header_data,
        file_filter: file_filter_data,
        file_tree: file_tree_data,
        diff_contents: diff_contents_data,
        codeowners: file_tree_data.codeowners,
        threads: thread_data,
        user: user_data,
        limit_config: @limit_config,
      )
    end

    sig { params(thread: PullRequestReviewThread).returns(Promise[PullRequests::PageData::Files::PageLimitConfig::ReviewCommentsLimitResult]) }
    private def thread_comments_promise(thread:)
      # There exists an edge case here in that the loader's max comments limit does not apply to pending comments,
      # but the `@limit_config`'s limiting will not take that into account.
      # Since we've based our limit on the P99 numbers, this shouldn't be an issue, but we can revisit if neeeded.
      @limit_config.apply_review_comments_limit do |limit|
        PullRequests::PageData::ThreadComments::Loader.load_async(current_user: @current_user,
          thread:,
          cap_filter: @cap_filter,
          max_comments: limit)
      end
    end

    sig { params(diff: GitHub::Diff).returns(T::Hash[String, Numeric]) }
    private def file_types_with_counts(diff)
      diff.deltas.each_with_object(Hash.new(0)) do |delta, hash|
        file_type = diff.get_file_type(delta.new_file.path || delta.old_file.path)
        hash[file_type] += 1 if file_type
      end
    end
  end
end
