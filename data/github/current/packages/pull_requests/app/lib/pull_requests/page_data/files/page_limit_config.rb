# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files
  # PageLimitConfig provides a framework for managing and enforcing limits on collections
  # of items in pull request pages. It helps prevent performance issues and improve user experience
  # by limiting the number of certain elements (like annotations) that can be displayed.
  #
  # How to add a new limit:
  # 1. Create a new limit class that inherits from BaseLimit
  #    class NewLimit < BaseLimit
  #      sig { override.returns(Integer) }
  #      def size
  #        # Return the maximum number of items allowed
  #        50
  #      end
  #    end
  #
  # 2. Add the new limit to the Limits struct
  #    class Limits < T::Struct
  #      const :annotations, AnnotationsLimit
  #      const :new_limit, NewLimit
  #    end
  #
  # 3. Add a new enum value to LimitType
  #    class LimitType < T::Enum
  #      enums do
  #        Annotations = new("annotations")
  #        NewLimit = new("new_limit")
  #      end
  #    end
  #
  # 4. Update the find_limit method to handle the new limit type
  #    sig { params(limit_type: LimitType).returns(BaseLimit) }
  #    def find_limit(limit_type)
  #      case limit_type
  #      when LimitType::Annotations
  #        @limits.annotations
  #      when LimitType::NewLimit
  #        @limits.new_limit
  #      end
  #    end
  #
  # 5. Initialize the new limit in the constructor
  #    @limits = T.let(Limits.new(annotations: AnnotationsLimit.new, new_limit: NewLimit.new), Limits)
  #
  # 6. Add a convenience method to check if the new limit has been exceeded
  #    sig { returns(T::Boolean) }
  #    def new_limit_exceeded?
  #      find_limit(LimitType::NewLimit).limit_exceeded?
  #    end
  #
  # Usage example:
  #   config = PageLimitConfig.new(repository: repo, user: current_user)
  #   limited_items = config.apply_page_limit(LimitType::NewLimit) do |limit|
  #     collection.take(limit)
  #   end
  class PageLimitConfig
    include GitHub::Memoizer
    # Base class for all limits
    class BaseLimit
      extend T::Helpers

      abstract!

      sig { void }
      def initialize
        @limit_exceeded = T.let(false, T::Boolean)
        @paginated_max_exceeded = T.let(false, T::Boolean)
      end

      sig { abstract.returns(Integer) }
      def size; end

      # Optional maximum limit when pagination is enabled.
      # Defaults to the same value as size.
      sig { overridable.returns(Integer) }
      def paginated_max
        size
      end

      sig { returns(T::Boolean) }
      def limit_exceeded?
        @limit_exceeded
      end

      sig { returns(T::Boolean) }
      def limit_exceeded!
        @limit_exceeded = true
      end

      sig { returns(T::Boolean) }
      def paginated_max_exceeded?
        @paginated_max_exceeded
      end

      sig { returns(T::Boolean) }
      def paginated_max_exceeded!
        @paginated_max_exceeded = true
      end
    end

    class AnnotationsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        50
      end

      sig { override.returns(Integer) }
      def paginated_max
        350
      end
    end

    class FilesLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        300
      end
    end

    class FilesWithSingleFileModeLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        1000
      end
    end

    # The stated limit for the Classic Rails experience
    class ClassicFilesLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        3000
      end
    end

    class LinesChanged < BaseLimit
      sig { override.returns(Integer) }
      def size
        10000
      end
    end

    class ReviewThreadsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        40
      end

      sig { override.returns(Integer) }
      def paginated_max
        350 # covers between p99.99 (~240 comments) and p99.999 (~500 comments) of thread distributions
      end
    end

    class ReviewCommentsPerThreadLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        20
      end
    end

    # Uses the same limits as review threads for now. We should look at the actual number of issue comments per PR to
    # set this limit more appropriately.
    class IssueCommentsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        40
      end

      sig { override.returns(Integer) }
      def paginated_max
        350
      end
    end

    # Uses the same limits as review threads for now. We should look at the actual number of review summaries per PR to
    # set this limit more appropriately.
    class ReviewSummaryCommentsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        40
      end

      sig { override.returns(Integer) }
      def paginated_max
        350
      end
    end

    class Limits < T::Struct
      const :annotations, AnnotationsLimit
      const :files, T.any(FilesLimit, FilesWithSingleFileModeLimit, ClassicFilesLimit)
      # The files changed count limit happens to be the same as the files limit
      # but the limit is applied differently for the tab counts
      const :files_changed_count, T.any(FilesLimit, FilesWithSingleFileModeLimit, ClassicFilesLimit)
      const :review_threads, ReviewThreadsLimit
      const :review_comments_per_thread, ReviewCommentsPerThreadLimit
      const :lines_changed, LinesChanged
      const :issue_comments, IssueCommentsLimit
      const :review_summary_comments, ReviewSummaryCommentsLimit
    end

    class LimitType < T::Enum
      enums do
        Annotations = new("annotations")
        Files = new("files")
        FilesChangedCount = new("files_changed_count")
        ReviewThreads = new("review_threads")
        ReviewCommentsPerThread = new("review_comments_per_thread")
        IssueComments = new("issue_comments")
        ReviewSummaryComments = new("review_summary_comments")
        LinesChanged = new("lines_changed")
      end
    end

    sig { params(repository: T.nilable(Repository), user: T.nilable(User), single_file_mode: T::Boolean, force_virtualization: T::Boolean).void }
    def initialize(repository: nil, user: nil, single_file_mode: false, force_virtualization: false)
      if single_file_mode && force_virtualization
        raise ArgumentError, "Cannot enable both single_file_mode and force_virtualization"
      end

      @repository = repository
      @user = user
      @single_file_mode_override_requested = single_file_mode
      @force_virtualization_override_requested = force_virtualization
      @limits = T.let(Limits.new(
        annotations: AnnotationsLimit.new,
        # temporary switch to use FilesWithSingleFileModeLimit if single file view is enabled
        # This will be removed once the feature is fully rolled out, we will up the limit to FilesLimit
        files: files_number_limit,
        files_changed_count: files_number_limit,
        review_threads: ReviewThreadsLimit.new,
        review_comments_per_thread: ReviewCommentsPerThreadLimit.new,
        lines_changed: LinesChanged.new,
        issue_comments: IssueCommentsLimit.new,
        review_summary_comments: ReviewSummaryCommentsLimit.new,
      ), Limits)
    end

    sig { returns(T.any(FilesLimit, FilesWithSingleFileModeLimit, ClassicFilesLimit)) }
    private def files_number_limit
      if files_3k_limit_enabled? || virtualization_enabled?
        ClassicFilesLimit.new
      elsif single_file_view_enabled?
        FilesWithSingleFileModeLimit.new
      else
        FilesLimit.new
      end
    end

    sig { params(limit_type: LimitType).returns(BaseLimit) }
    def find_limit(limit_type)
      case limit_type
      when LimitType::Annotations
        @limits.annotations
      when LimitType::ReviewThreads
        @limits.review_threads
      when LimitType::Files
        @limits.files
      when LimitType::FilesChangedCount
        @limits.files_changed_count
      when LimitType::ReviewCommentsPerThread
        @limits.review_comments_per_thread
      when LimitType::IssueComments
        @limits.issue_comments
      when LimitType::ReviewSummaryComments
        @limits.review_summary_comments
      when LimitType::LinesChanged
        @limits.lines_changed
      end
    end

    # Applies a limit to a generic collection of objects.
    # Optionally checks if a secondary max limit is exceeded using a count block.
    #
    # @param limit_type [LimitType] The type of limit to apply
    # @param count_exceeds_paginated_max_block [Proc, nil] Optional block that receives the paginated max limit
    #   and returns true if the total count exceeds paginated max. Use for efficient existence checks
    #   like `relation.offset(paginated_max).exists?` to avoid loading all records.
    # @yield [limit] Block that receives limit + 1 and returns the collection
    # @return [Enumerable] The limited collection
    sig do
      type_parameters(:T).params(
        limit_type: LimitType,
        count_exceeds_paginated_max_block: T.nilable(T.proc.params(paginated_max: Integer).returns(T::Boolean)),
        block: T.proc.params(limit: Integer).returns(T::Enumerable[T.type_parameter(:T)])
      ).returns(T::Enumerable[T.type_parameter(:T)])
    end
    def apply_page_limit(limit_type, count_exceeds_paginated_max_block: nil, &block)
      if apply_limits_enabled?
        limit = find_limit(limit_type)
        collection_limit = limit.size
        # Pass the collection limit + 1 to the block to see if the limit is exceeded
        collection = yield collection_limit + 1

        # Limit the collection returned to the actual size limit
        # Mark the limit as exceeded
        if collection.to_a.size > collection_limit
          collection = collection.take(collection_limit)
          limit.limit_exceeded!
        end

        # Check if max limit is exceeded using an efficient count check
        # Only run when: base limit exceeded, block provided, and max differs from size
        if limit.limit_exceeded? && limit.paginated_max != limit.size && count_exceeds_paginated_max_block
          if count_exceeds_paginated_max_block.call(limit.paginated_max)
            limit.paginated_max_exceeded!
          end
        end

        collection
      else
        # Yield an arbitrarily high limit while this is being rolled out
        collection = yield 1000
        collection
      end
    end

    sig do
      type_parameters(:T).params(
        limit_type: LimitType,
        block: T.proc.params(limit: Integer).returns(T::Enumerable[T.type_parameter(:T)])
      ).returns(T::Enumerable[T.type_parameter(:T)])
    end
    def apply_paginated_max_limit(limit_type, &block)
      if apply_limits_enabled?
        limit = find_limit(limit_type)
        collection_limit = limit.paginated_max
        # Pass the paginated max limit + 1 to the block to see if the paginated max limit is exceeded
        collection = yield collection_limit + 1

        # Mark the paginated max limit as exceeded if the block indicates it is exceeded
        if collection.to_a.size > collection_limit
          collection = collection.take(collection_limit)
          limit.paginated_max_exceeded!
        end

        collection
      else
        # Yield an arbitrarily high limit while this is being rolled out
        collection = yield 1000
        collection
      end
    end

    # Applies a limit to the number of diff summaries and diff entries shown
    # Max files does not apply to the summary, so we need to truncate the list ourselves
    # Max files does apply to the number of diff entries
    sig do
      params(
        diff: GitHub::Diff,
        block: T.nilable(T.proc.returns(T::Enumerable[GitRPC::Diff::Summary::Delta]))
      ).returns(T.nilable(T::Enumerable[GitRPC::Diff::Summary::Delta]))
    end
    def apply_files_page_limit(diff, &block)
      if apply_limits_enabled?
        files_limit_object = find_limit(LimitType::Files)
        diff.max_files = files_limit

        if block_given?
          diff_summaries = yield
          if diff.too_big?
            files_limit_object.limit_exceeded!
          end

          T.must(diff_summaries.first(files_limit))
        end
      else
        if block_given?
          yield
        end
      end
    end

    # Applies a limit to the file count
    sig do
      params(
        block: T.proc.returns(Integer)
      ).returns(Integer)
    end
    def apply_files_changed_count_limit(&block)
      if apply_limits_enabled?
        files_limit_object = find_limit(LimitType::FilesChangedCount)

        files_count = yield
        if files_count > files_limit
          files_limit_object.limit_exceeded!
          return files_limit
        end
        files_count
      else
        yield
      end
    end

    # Returns true if the single file mode should be used for the diff.
    # This is determined by the single_file_view_enabled feature flag
    # and whether the total number of changed lines in the diff exceeds
    # the limit.
    # @single_file_mode exists as a URL param override `?mode=single`
    sig do
      params(
      diff: GitHub::Diff
    ).returns(T::Boolean)
    end
    def use_single_file_mode?(diff)
      # Force virtualization takes precedence - never use single file mode
      return false if @force_virtualization_override_requested

      if single_file_view_enabled?
        if @single_file_mode_override_requested || !virtualization_enabled? && exceeds_difflines_display_limits?(diff)
          lines_changed_limit_object = find_limit(LimitType::LinesChanged)
          lines_changed_limit_object.limit_exceeded!
          return true
        end
      end
      false
    end

    # @force_virtualization_override_requested exists as a URL param override `?mode=virtualization`
    sig do
      params(
        diff: GitHub::Diff
      ).returns(T::Boolean)
    end
    def use_virtualization?(diff)
      # Force virtualization override - always use virtualization
      if @force_virtualization_override_requested
        lines_changed_limit_object = find_limit(LimitType::LinesChanged)
        lines_changed_limit_object.limit_exceeded!
        return true
      end

      if virtualization_enabled? && exceeds_difflines_display_limits?(diff)
        lines_changed_limit_object = find_limit(LimitType::LinesChanged)
        lines_changed_limit_object.limit_exceeded!
        return true
      end
      false
    end

    sig do
      params(
        diff: GitHub::Diff
      ).returns(T::Boolean)
    end
    def exceeds_difflines_display_limits?(diff)
      lines_changed_limit_object = find_limit(LimitType::LinesChanged)
      total_changed_lines = calculate_total_changed_lines(diff)

      total_changed_lines > lines_changed_limit_object.size
    end

    class ReviewCommentsLimitResult < T::Struct
      const :review_comments, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
      const :review_comments_limit_exceeded, T::Boolean
    end

    # Applies a limit to a collection of review comments
    # Implementation differs because we need to store whether the comment limit was exceeded
    # on a per thread basis
    sig do
      params(
        block: T.proc.params(limit: Integer).returns(
          T::Hash[Integer, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]]
        )
      ).returns(
        T::Hash[Integer, PullRequests::PageData::Files::PageLimitConfig::ReviewCommentsLimitResult]
      )
    end
    def apply_review_comments_per_thread_limit(&block)
      if apply_limits_enabled?
        limit = find_limit(LimitType::ReviewCommentsPerThread)
        collection_limit = limit.size

        result = yield collection_limit + 1

        result.transform_values do |comments|
          comments_limit_exceeded = comments.count > collection_limit

          ReviewCommentsLimitResult.new(
            review_comments: comments.take(collection_limit),
            review_comments_limit_exceeded: comments_limit_exceeded,
          )
        end
      else
        # Yield an arbitrarily high limit while this is being rolled out
        result = yield 1000

        result.transform_values do |comments|
          ReviewCommentsLimitResult.new(
            review_comments: comments.to_a,
            review_comments_limit_exceeded: false,
          )
        end
      end
    end

    sig { returns(Integer) }
    def annotations_limit
      find_limit(LimitType::Annotations).size
    end

    sig { returns(T::Boolean) }
    def annotations_limit_exceeded?
      find_limit(LimitType::Annotations).limit_exceeded?
    end

    sig { returns(T::Boolean) }
    def annotations_paginated_limit_exceeded?
      find_limit(LimitType::Annotations).paginated_max_exceeded?
    end

    sig { returns(Integer) }
    def annotations_paginated_limit
      find_limit(LimitType::Annotations).paginated_max
    end

    sig { returns(Integer) }
    def review_threads_limit
      find_limit(LimitType::ReviewThreads).size
    end

    sig { returns(T::Boolean) }
    def review_threads_limit_exceeded?
      find_limit(LimitType::ReviewThreads).limit_exceeded?
    end

    sig { returns(T::Boolean) }
    def review_threads_paginated_limit_exceeded?
      find_limit(LimitType::ReviewThreads).paginated_max_exceeded?
    end

    sig { returns(Integer) }
    def review_threads_paginated_limit
      limit = find_limit(LimitType::ReviewThreads)
      limit.paginated_max
    end

    sig { returns(Integer) }
    def files_limit
      find_limit(LimitType::Files).size
    end

    sig { returns(T::Boolean) }
    def files_limit_exceeded?
      find_limit(LimitType::Files).limit_exceeded?
    end

    sig { returns(T::Boolean) }
    def files_changed_count_limit_exceeded?
      find_limit(LimitType::FilesChangedCount).limit_exceeded?
    end

    sig { returns(Integer) }
    def lines_changed_limit
      find_limit(LimitType::LinesChanged).size
    end

    sig { returns(T::Boolean) }
    def lines_changed_limit_exceeded?
      find_limit(LimitType::LinesChanged).limit_exceeded?
    end

    sig { returns(Integer) }
    def review_comments_per_thread_limit
      find_limit(LimitType::ReviewCommentsPerThread).size
    end

    sig { returns(Integer) }
    def issue_comments_limit
      find_limit(LimitType::IssueComments).size
    end

    sig { returns(T::Boolean) }
    def issue_comments_limit_exceeded?
      find_limit(LimitType::IssueComments).limit_exceeded?
    end

    sig { returns(T::Boolean) }
    def issue_comments_paginated_limit_exceeded?
      find_limit(LimitType::IssueComments).paginated_max_exceeded?
    end

    sig { returns(Integer) }
    def issue_comments_paginated_limit
      find_limit(LimitType::IssueComments).paginated_max
    end

    sig { returns(Integer) }
    def review_summary_comments_limit
      find_limit(LimitType::ReviewSummaryComments).size
    end

    sig { returns(T::Boolean) }
    def review_summary_comments_limit_exceeded?
      find_limit(LimitType::ReviewSummaryComments).limit_exceeded?
    end

    sig { returns(T::Boolean) }
    def review_summary_comments_paginated_limit_exceeded?
      find_limit(LimitType::ReviewSummaryComments).paginated_max_exceeded?
    end

    sig { returns(Integer) }
    def review_summary_comments_paginated_limit
      find_limit(LimitType::ReviewSummaryComments).paginated_max
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def apply_limits_enabled?
      if @user.nil?
        # For anonymous users, check the global feature flag
        return FeatureFlag.vexi.enabled?(:pr_files_anon, default: false)
      end

      return false unless @user.feature_flag_enabled?(:prx_files, default: false)

      @user.feature_preview_enabled?(:prx_files, enrolled_by_default_override: @user.feature_flag_enabled?(:prx_files_opt_out_by_default, default: false))
    end

    # If single file mode is allowed to be used
    sig { returns(T.nilable(T::Boolean)) }
    memoize def single_file_view_enabled?
      FeatureFlag.vexi.enabled?(:prx_files_single_file_mode, @user, default: false) || @single_file_mode_override_requested
    end

    sig { returns(T::Boolean) }
    memoize private def virtualization_enabled?
      @force_virtualization_override_requested || !@single_file_mode_override_requested && (@user&.feature_preview_enabled?(:pull_request_files_virtualization) || FeatureFlag.vexi.enabled?(:pull_request_files_virtualization_ga, default: false))
    end

    sig { params(diff: GitHub::Diff).returns(Integer) }
    private def calculate_total_changed_lines(diff)
      # Exclude hidden by default files from being counted towards the diff line count:
      # - Removed files
      # - Files with more than max_diff_lines changed lines (defaults to 3000)
      # This does not cover large file size (byte size)
      changed_lines_to_exclude = diff.summary.deltas.sum do |delta|
        # binary files are not counted towards the changed lines limit
        # binary files both additions and deletions are nil
        if delta.binary?
          0
        else
          delta.removed? || delta.changes > diff.max_diff_lines ? delta.changes : 0
        end
      end

      diff.summary.changes - changed_lines_to_exclude
    end

    sig { returns(T::Boolean) }
    memoize def files_3k_limit_enabled?
      FeatureFlag.vexi.enabled?(:pr_files_3k_limit, @user, default: false)
    end
  end
end
