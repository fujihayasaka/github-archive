# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  class Loader
    include PullRequests::PageData::Telemetry
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
      const :resolved_by, T.nilable(User)
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

    class Notice < T::Struct
      const :name, String
      const :dismissed, T::Boolean
    end

    class UserData < T::Struct
      const :can_comment, T::Boolean
      const :tab_size, T.nilable(Integer)
      const :notices, T::Array[Notice]
    end

    class ComparisonRange < T::Struct
      const :base_oid, String
      const :head_oid, String
    end

    class ComparisonData < T::Struct
      const :historical_comparison, ComparisonRange
      const :current_comparison, ComparisonRange
      const :merge_base_oid, String
      const :is_current, T::Boolean
    end

    class Data < T::Struct
      const :diff_contents, PullRequests::PageData::Diffs::Contents::Loader::Data
      const :toolbar, PullRequests::PageData::Files::Toolbar::Loader::Data
      const :file_filter, FileFilterData
      const :file_tree, PullRequests::PageData::Files::FileTree::Loader::Data
      const :header, T::Hash[String, T.untyped]
      const :codeowners, T.nilable(PullRequests::PageData::Codeowners::Loader::Data)
      const :comparison, ComparisonData
      const :threads, T::Array[PullRequestThreadData]
      const :user, UserData
      const :limit_config, PullRequests::PageData::Files::PageLimitConfig
      const :single_file_mode, T::Boolean
      const :change_group_generation, PullRequests::PageData::ChangeGroupGeneration::Loader::Data
      const :enable_diff_consolidation, T::Boolean
      const :commit, T.nilable(PullRequests::PageData::Commit::Loader::Data)
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
        short_path: T.nilable(String)
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
      include_codeowners: false,
      short_path: nil
    )
      new(
        comparison:,
        ignore_whitespace:,
        pull_request:,
        timeout:,
        cap_filter:,
        highlighting_strategy:,
        user_session:,
        limit_config:,
        current_user:,
        file_filter:,
        include_codeowners:,
        short_path:
      ).load
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
        short_path: T.nilable(String)
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
      include_codeowners:,
      short_path:
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
      @short_path = short_path
      @single_file_mode = T.let(limit_config.use_single_file_mode?(comparison.diff), T::Boolean)
    end

    sig { returns(Data) }
    def load
      with_telemetry do
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

        paths = @single_file_mode ? [T.must(file_tree_data.diffs[0]).path] : []

        context_lines = file_tree_data.context_injection_ranges

        diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
          current_user: @current_user,
          # Duplicate diff because loading thread previews interferes with the limits here
          diff: @comparison.diff.dup,
          ignore_whitespace: @ignore_whitespace,
          timeout: @timeout,
          highlighting_strategy: @highlighting_strategy,
          top_only: true,
          repository: @pull_request.compare_repository,
          pull_request: @pull_request,
          viewed_files: file_tree_data.viewed_files,
          limit_config: @limit_config,
          paths: paths,
          short_path: @short_path,
          context_lines:,
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

        thread_data = load_thread_data(threads)

        user_data = UserData.new(
          can_comment: @current_user ? @pull_request.issue&.can_comment?(@current_user) : false,
          tab_size: @current_user&.settings&.get(:tab_size),
          notices: user_notices,
        )

        change_group_generation_data = PullRequests::PageData::ChangeGroupGeneration::Loader.load(
          comparison: @comparison,
          current_user: @current_user,
          pull_request: @pull_request,
        )

        # Load commit data if we're viewing a single commit in a historical comparison
        # Check if start_commit is a parent of end_commit (single commit view)
        # and we're not viewing the current/full PR range
        commit_data = \
          if @comparison.end_commit.parent_oids.include?(@comparison.start_commit.oid) && !@comparison.current?
            PullRequests::PageData::Commit::Loader.load(
              commit: @comparison.end_commit,
              current_user: @current_user,
            )
          end

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
          single_file_mode: @single_file_mode,
          change_group_generation: change_group_generation_data,
          enable_diff_consolidation: FeatureFlag.vexi.enabled?(:prx_diff_consolidation, @current_user, default: false),
          commit: commit_data,
          comparison: comparison_data
        )
      end
    end

    sig { params(threads: T::Enumerable[PullRequestReviewThread]).returns(T::Hash[Integer, PullRequests::PageData::Files::PageLimitConfig::ReviewCommentsLimitResult]) }
    private def load_comments_by_thread_id(threads)
      # There exists an edge case here in that the loader's max comments limit does not apply to pending comments,
      # but the `@limit_config`'s limiting will not take that into account.
      # Since we've based our limit on the P99 numbers, this shouldn't be an issue, but we can revisit if neeeded.
      @limit_config.apply_review_comments_per_thread_limit do |limit|
        PullRequests::PageData::ThreadComments::Loader.load(
          current_user: @current_user,
          threads: threads,
          cap_filter: @cap_filter,
          max_comments: limit)
      end
    end

    sig { params(threads: T::Enumerable[PullRequestReviewThread]).returns(T::Array[PullRequestThreadData]) }
    private def load_thread_data(threads)
      thread_result_by_thread_id = load_comments_by_thread_id(threads)

      thread_promises = threads.map do |thread|
        Promise.all([
          thread.async_viewer_can_reply?(@current_user),
          thread.async_resolver_for(@current_user)
        ]).then do |viewer_can_reply, resolved_by|
          thread_result = thread_result_by_thread_id[thread.id]

          next unless thread_result

          PullRequestThreadData.new(
            id: thread.id,
            is_resolved: thread.resolved?,
            resolved_by: resolved_by,
            viewer_can_reply: viewer_can_reply,
            thread_comments: thread_result.review_comments,
            subject_type: thread.subject_type,
            review_comments_limit_exceeded: thread_result.review_comments_limit_exceeded,
            review_comments_limit: @limit_config.review_comments_per_thread_limit,
          )
        end
      end

      Promise.all(thread_promises).sync
    end

    sig { params(diff: GitHub::Diff).returns(T::Hash[String, Numeric]) }
    private def file_types_with_counts(diff)
      diff.deltas.each_with_object(Hash.new(0)) do |delta, hash|
        file_type = diff.get_file_type(delta.new_file.path || delta.old_file.path)
        hash[file_type] += 1 if file_type
      end
    end

    sig { returns(T::Array[Notice]) }
    private def user_notices
      return [] unless @current_user

      compact_diff_lines_notice = Notice.new(
        name: UserNotice::COMPACT_DIFF_LINES_NOTICE,
        dismissed: @current_user.dismissed_notice?(UserNotice::COMPACT_DIFF_LINES_NOTICE)
      )
      single_file_notice = Notice.new(
        name: UserNotice::SINGLE_FILE_MODE_NOTICE,
        dismissed: @current_user.dismissed_notice?(UserNotice::SINGLE_FILE_MODE_NOTICE)
      )

      [compact_diff_lines_notice, single_file_notice]
    end

    sig { returns(ComparisonData) }
    private def comparison_data
      ComparisonData.new(
        historical_comparison: ComparisonRange.new(
          base_oid: @pull_request.historical_comparison.async_base_oid.sync,
          head_oid: @pull_request.historical_comparison.async_head_oid.sync
        ),
        current_comparison: ComparisonRange.new(
          base_oid: @comparison.start_commit.oid,
          head_oid: @comparison.end_commit.oid
        ),
        merge_base_oid: @comparison.base_commit.oid,
        is_current: @comparison.current?
      )
    end
  end
end
