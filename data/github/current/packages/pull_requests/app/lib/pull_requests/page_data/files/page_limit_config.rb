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
      end

      sig { abstract.returns(Integer) }
      def size; end

      sig { returns(T::Boolean) }
      def limit_exceeded?
        @limit_exceeded
      end

      sig { returns(T::Boolean) }
      def limit_exceeded!
        @limit_exceeded = true
      end
    end

    class AnnotationsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        50
      end
    end

    class ReviewThreadsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        40
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

    class LinesChanged < BaseLimit
      sig { override.returns(Integer) }
      def size
        6000
      end
    end

    class ReviewCommentsPerThreadLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        20
      end
    end

    class ListedFileLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        300
      end
    end

    class Limits < T::Struct
      const :annotations, AnnotationsLimit
      const :files, T.any(FilesLimit, FilesWithSingleFileModeLimit)
      # The files changed count limit happens to be the same as the files limit
      # but the limit is applied differently for the tab counts
      const :files_changed_count, T.any(FilesLimit, FilesWithSingleFileModeLimit)
      const :review_threads, ReviewThreadsLimit
      const :review_comments_per_thread, ReviewCommentsPerThreadLimit
      const :listed_files, ListedFileLimit
      const :lines_changed, LinesChanged
    end

    class LimitType < T::Enum
      enums do
        Annotations = new("annotations")
        Files = new("files")
        FilesChangedCount = new("files_changed_count")
        ReviewThreads = new("review_threads")
        ReviewCommentsPerThread = new("review_comments_per_thread")
        ListedFiles = new("listed_files")
        LinesChanged = new("lines_changed")
      end
    end

    sig { params(repository: T.nilable(Repository), user: T.nilable(User), single_file_mode: T::Boolean).void }
    def initialize(repository: nil, user: nil, single_file_mode: false)
      @repository = repository
      @user = user
      @single_file_mode = single_file_mode
      @limits = T.let(Limits.new(
        annotations: AnnotationsLimit.new,
        # temporary switch to use FilesWithSingleFileModeLimit if single file view is enabled
        # This will be removed once the feature is fully rolled out, we will up the limit to FilesLimit
        files: single_file_view_enabled? ? FilesWithSingleFileModeLimit.new : FilesLimit.new,
        files_changed_count: single_file_view_enabled? ? FilesWithSingleFileModeLimit.new : FilesLimit.new,
        review_threads: ReviewThreadsLimit.new,
        review_comments_per_thread: ReviewCommentsPerThreadLimit.new,
        listed_files: ListedFileLimit.new,
        lines_changed: LinesChanged.new
      ), Limits)
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
      when LimitType::ListedFiles
        @limits.listed_files
      when LimitType::LinesChanged
        @limits.lines_changed
      end
    end

    # Applies a limit to a generic collection of objects
    sig { type_parameters(:T).params(limit_type: LimitType, block: T.proc.params(limit: Integer).returns(T::Enumerable[T.type_parameter(:T)])).returns(T::Enumerable[T.type_parameter(:T)]) }
    def apply_page_limit(limit_type, &block)
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
      if single_file_view_enabled?
        lines_changed_limit = find_limit(LimitType::LinesChanged)
        total_changed_lines = diff.summary.changes

        if @single_file_mode || total_changed_lines > lines_changed_limit.size
          lines_changed_limit.limit_exceeded!
          return true
        end
      end
      false
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

    sig { returns(Integer) }
    def review_threads_limit
      find_limit(LimitType::ReviewThreads).size
    end

    sig { returns(T::Boolean) }
    def review_threads_limit_exceeded?
      find_limit(LimitType::ReviewThreads).limit_exceeded?
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
    def review_comments_per_thread_limit
      find_limit(LimitType::ReviewCommentsPerThread).size
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def apply_limits_enabled?
      return false unless @user && @user.feature_flag_enabled?(:prx_files, default: false)

      @user.feature_preview_enabled?(:prx_files, enrolled_by_default_override: @user.feature_flag_enabled?(:prx_files_opt_out_by_default, default: false))
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def single_file_view_enabled?
      FeatureFlag.vexi.enabled?(:prx_files_single_file_mode, @user, default: false) || @single_file_mode
    end
  end
end
