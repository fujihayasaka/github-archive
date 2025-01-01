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

    class ReviewCommentsLimit < BaseLimit
      sig { override.returns(Integer) }
      def size
        20
      end
    end

    class Limits < T::Struct
      const :annotations, AnnotationsLimit
      const :files, FilesLimit
      # The files changed count limit happens to be the same as the files limit
      # but the limit is applied differently for the tab counts
      const :files_changed_count, FilesLimit
      const :review_threads, ReviewThreadsLimit
      const :review_comments, ReviewCommentsLimit
    end

    class LimitType < T::Enum
      enums do
        Annotations = new("annotations")
        Files = new("files")
        FilesChangedCount = new("files_changed_count")
        ReviewThreads = new("review_threads")
        ReviewComments = new("review_comments")
      end
    end

    sig { params(repository: T.nilable(Repository), user: T.nilable(User)).void }
    def initialize(repository: nil, user: nil)
      @repository = repository
      @user = user
      @limits = T.let(Limits.new(
        annotations: AnnotationsLimit.new,
        files: FilesLimit.new,
        files_changed_count: FilesLimit.new,
        review_threads: ReviewThreadsLimit.new,
        review_comments: ReviewCommentsLimit.new
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
      when LimitType::ReviewComments
        @limits.review_comments
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

    class ReviewCommentsLimitResult < T::Struct
      const :review_comments, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
      const :review_comments_limit_exceeded, T::Boolean
    end

    # Applies a limit to a collection of review comments
    # Implementation differs because we load review comments as promises
    sig do
      params(
        block: T.proc.params(limit: Integer).returns(
          Promise[T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]]
        )
      ).returns(
        Promise[PullRequests::PageData::Files::PageLimitConfig::ReviewCommentsLimitResult]
      )
    end
    def apply_review_comments_limit(&block)
      if apply_limits_enabled?
        limit = find_limit(LimitType::ReviewComments)
        collection_limit = limit.size

        result = yield collection_limit + 1

        result.then do |comments|
          comments_limit_exceeded = comments.to_a.size > collection_limit

          ReviewCommentsLimitResult.new(
            review_comments: comments.take(collection_limit),
            review_comments_limit_exceeded: comments_limit_exceeded,
          )
        end
      else
        # Yield an arbitrarily high limit while this is being rolled out
        result = yield 1000

        result.then do |comments|
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
    def review_comments_limit
      find_limit(LimitType::ReviewComments).size
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def apply_limits_enabled?
      return false unless @user && @user.feature_enabled?(:prx_files)

      @user.feature_preview_enabled?(:prx_files)
    end
  end
end
