# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::FileTree
  class Loader
    include GitHub::ResilienceMixin
    include GitHub::Memoizer
    include PullRequests::PageData::Telemetry

    CONTEXT_LINES = 3

    module MarkerPosition
      extend T::Helpers
      interface!
      sealed!

      sig { abstract.returns(T.nilable(T::Range[Integer])) }
      def context_injection_range; end

      class File
        include MarkerPosition

        # Don't call `.new` directly!
        # Use `.instance` instead.
        private_class_method :new

        sig { returns(File) }
        def self.instance
          @instance ||= T.let(new, T.nilable(File))
        end

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          other.is_a?(File)
        end

        sig { override.returns(T.nilable(T::Range[Integer])) }
        def context_injection_range = nil
      end

      class Line < T::Struct
        include MarkerPosition

        # Don't call `.new` directly!
        # Use `.left` or `.right` instead.
        private_class_method :new

        sig { params(line: Integer).returns(Line) }
        def self.right(line) = new(line:, side: "R")

        sig { params(line: Integer).returns(Line) }
        def self.left(line) = new(line:, side: "L")

        sig { params(line: Integer, left_sided: T::Boolean).returns(Line) }
        def self.line(line, left_sided:) = left_sided ? left(line) : right(line)

        sig { params(diff_line: GitHub::Diff::Line).returns(Line) }
        def self.from_diff_line(diff_line)
          # TODO: Handle `DiffLine#type == :empty`
          if diff_line.deletion?
            left(diff_line.left)
          else
            right(diff_line.right)
          end
        end

        const :line, Integer
        const :side, String

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          other.is_a?(Line) && other.line == line && other.side == side
        end

        sig { override.returns(T.nilable(T::Range[Integer])) }
        def context_injection_range
          # Context injected lines are always from the right side. If a
          # marker is on the left side, it's definitely part of the diff
          # and doesn't need any additional context injection.
          return if side == "L"

          start_line = [line - CONTEXT_LINES, 1].max
          end_line = line + CONTEXT_LINES
          (start_line..end_line)
        end
      end

      class LineRange < T::Struct
        include MarkerPosition

        sig { params(start_diff_line: GitHub::Diff::Line, end_diff_line: GitHub::Diff::Line).returns(LineRange) }
        def self.from_diff_lines(start_diff_line, end_diff_line)
          start_line = MarkerPosition::Line.from_diff_line(start_diff_line)
          end_line = MarkerPosition::Line.from_diff_line(end_diff_line)
          new(start_line:, end_line:)
        end

        const :start_line, Line
        const :end_line, Line

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          other.is_a?(LineRange) &&
            other.start_line == start_line &&
            other.end_line == end_line
        end

        sig { override.returns(T.nilable(T::Range[Integer])) }
        def context_injection_range
          start_range, end_range = start_line.context_injection_range, end_line.context_injection_range

          # Context injected lines are always on the right side.
          return if start_range.nil? || end_range.nil?

          start_range.begin..end_range.end
        end
      end
    end

    class ThreadSummary < T::Struct
      const :id, Integer
      const :position, MarkerPosition
      const :outdated_reason, T.nilable(String), default: nil
    end

    class AnnotationSummary < T::Struct
      const :id, Integer
      const :position, MarkerPosition
      const :level, String
    end

    class DiffSummary < T::Struct
      const :path, String
      const :change_type, Diffs::Entry::ChangeType
      const :is_codeowner, T.nilable(T::Boolean)
      const :is_manifest_file, T::Boolean
      const :is_vendored, T::Boolean
      const :threads, T::Array[ThreadSummary]
      const :annotations, T::Array[AnnotationSummary]
      const :lines_added, Integer
      const :lines_deleted, Integer
      const :lines_changed, Integer

      sig { returns(T::Boolean) }
      def vendored? = is_vendored

      sig { returns(T::Boolean) }
      def is_removed?
        [Diffs::Entry::ChangeType::Removed, Diffs::Entry::ChangeType::Deleted].include?(change_type)
      end

      sig { returns(T::Array[T::Range[Integer]]) }
      def context_injection_ranges
        threads.chain(annotations).filter_map { _1.position.context_injection_range }.uniq
      end
    end

    class Data < T::Struct
      const :base_ref_oid, String
      const :codeowners, T.nilable(::PullRequests::PageData::Codeowners::Loader::Data)
      const :commits, T::Array[Commit]
      const :diffs, T::Array[DiffSummary]
      const :last_review_oid, T.nilable(String)
      const :pull_request, ::PullRequest
      const :repository, Repository
      const :viewed_files, PullRequestUserReviews
      const :feature_flags, T::Hash[Symbol, T::Boolean], factory: -> { Hash.new }

      sig { returns(T::Hash[String, T::Array[T::Range[Integer]]]) }
      def context_injection_ranges
        diffs.each_with_object({}) do |diff, result|
          result[diff.path] = diff.context_injection_ranges
        end
      end
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        end_commit_oid: String,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        current_user: T.nilable(User),
        include_codeowners: T::Boolean,
      ).returns(Data)
    end
    def self.load(
      comparison:,
      pull_request:,
      cap_filter:,
      user_session:,
      end_commit_oid:,
      limit_config:,
      current_user: nil,
      include_codeowners: false
    )
      new(comparison:, pull_request:, cap_filter:, user_session:, end_commit_oid:, limit_config:, current_user:, include_codeowners:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        pull_request: ::PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        user_session: T.nilable(UserSession),
        end_commit_oid: String,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        current_user: T.nilable(User),
        include_codeowners: T::Boolean,
      ).void
    end
    def initialize(
      comparison:,
      pull_request:,
      cap_filter:,
      user_session:,
      end_commit_oid:,
      limit_config:,
      current_user:,
      include_codeowners:
    )
      @comparison = comparison
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
      @end_commit_oid = end_commit_oid
      @limit_config = limit_config
      @user_session = user_session
      @include_codeowners = include_codeowners
    end

    sig { returns(Data) }
    def load
      with_telemetry do
        show_unchanged_files = repository.feature_flag_enabled?(:prx_unchanged_files_in_file_tree, default: false)
        thread_data = load_thread_data

        if show_unchanged_files
          # we'll need to revisit how this affect page_limits when we circle back to unchanged files
          annotation_data = load_annotations_data(paths: nil)
          paths_with_markers = (thread_data.keys + annotation_data.keys).uniq
        else
          paths_with_markers = []
        end

        diff_summaries = PullRequests::PageData::Diffs::Summary::Loader.load(
          diff: @comparison.diff,
          repository:,
          paths_with_markers:,
          limit_config: @limit_config,
        ).summaries.sort_by { PullRequests::PageData::Diffs::Summary::ComparablePath.new(_1.path) }

        unless show_unchanged_files
          # If we are not showing unchanged files, we only load annotations for changed files.
          # This is to avoid loading annotations for files that are not changed.
          annotation_data = load_annotations_data(paths: diff_summaries.map(&:path))
        end

        codeowners_data = load_codeowners_data(diff_summaries.map(&:path))

        diffs = diff_summaries.map do |diff_summary|
          path = diff_summary.path
          DiffSummary.new(
            path: path,
            change_type: diff_summary.change_type,
            is_codeowner: codeowners_data&.is_owned_by_viewer?(path),
            is_vendored: diff_summary.is_vendored,
            is_manifest_file: diff_summary.is_manifest_file,
            threads: thread_data[path] || [],
            annotations: annotation_data[path] || [],
            lines_added: diff_summary.lines_added,
            lines_deleted: diff_summary.lines_deleted,
            lines_changed: diff_summary.lines_changed,
          )
        end

        Data.new(
          base_ref_oid: @comparison.start_commit.oid,
          commits: @pull_request.changed_commits,
          diffs: diffs,
          last_review_oid: last_review_oid,
          pull_request: @pull_request,
          repository:,
          viewed_files: PullRequestUserReviews.new(@pull_request, @current_user),
          codeowners: codeowners_data,
          feature_flags:,
        )
      end
    end

    private

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def feature_flags
      Hash[[
        :pull_request_diff_context_injection,
      ].map do |ff|
        [ff, !!@pull_request.repository&.feature_flag_enabled?(ff, default: false)]
      end]
    end

    sig { returns(Repository) }
    def repository = T.must(@pull_request.repository)

    sig { params(paths: T.nilable(T::Array[String])).returns(T::Hash[String, T::Array[AnnotationSummary]]) }
    def load_annotations_data(paths:)
      with_database_error_fallback(fallback: {}) do
        result = T.let({}, T::Hash[String, T::Array[AnnotationSummary]])

        annotations = @limit_config.apply_page_limit(
          PullRequests::PageData::Files::PageLimitConfig::LimitType::Annotations
        ) do |limit|
          relation = @pull_request.compare_repository.annotations_for(
            inline_only: true,
            limit: limit,
            sha: @end_commit_oid,
            filenames: paths || []
          )
          relation.pluck(
            :id, :filename, :start_line, :end_line, :annotation_level
          )
        end

        annotations.each do |id, path, start_line, end_line, level|
          if start_line + 1 == end_line
            position = MarkerPosition::Line.right(end_line)
          else
            position = MarkerPosition::LineRange.new(
              start_line: MarkerPosition::Line.right(start_line + 1),
              end_line: MarkerPosition::Line.right(end_line),
            )
          end

          result[path] ||= []
          T.must(result[path]) << AnnotationSummary.new(id:, position:, level:)
        end

        result
      end
    end

    sig { returns(T::Hash[String, T::Array[ThreadSummary]]) }
    def load_thread_data
      with_database_error_fallback(fallback: {}) do
        # TODO: Depend on the DB-cached values of the new fields unless filtering
        #   by commit.

        result = T.let({}, T::Hash[String, T::Array[ThreadSummary]])
        diff = @comparison.diff

        # Filter out threads that are not visible to the current user.
        threads = @limit_config.apply_page_limit(
          PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads
        ) do |limit|
          @pull_request.review_threads.visible_to(@current_user).limit(limit)
        end

        if FeatureFlag.vexi.enabled?(:prx_comment_outside_the_diff, repository, repository.owner, default: false)
          PullRequests::CommentPosition.from_pull_request_threads(
            pull_request: @pull_request,
            threads: threads.to_a,
            destination_base_commit_oid: @comparison.start_commit.oid,
            destination_head_commit_oid: @comparison.end_commit.oid,
            position_only: true, # Reduce GitRPC traffic as much as we can!
          ).each do |thread, value|
            position = begin
              case value
              when PullRequests::CommentPosition::Errors
                outdated_reason = "errors"
                MarkerPosition::File.instance
              else
                case positioning = value.positioning
                when PullRequests::CommentPosition::Positions::Line
                  MarkerPosition::Line.line(
                    positioning.line,
                    left_sided: positioning.commit_oid == positioning.base_commit_oid
                  )
                when PullRequests::CommentPosition::Positions::Multiline
                  MarkerPosition::LineRange.new(
                    start_line: MarkerPosition::Line.line(
                      positioning.start_line,
                      left_sided: positioning.start_commit_oid == positioning.base_commit_oid,
                    ),
                    end_line: MarkerPosition::Line.line(
                      positioning.end_line,
                      left_sided: positioning.end_commit_oid == positioning.base_commit_oid,
                    ),
                  )
                when PullRequests::CommentPosition::Positions::File
                  MarkerPosition::File.instance
                when PullRequests::CommentPosition::Positions::Indeterminate
                  outdated_reason = positioning.reason.to_s
                  MarkerPosition::File.instance
                when PullRequests::CommentPosition::Positions::Errored
                  outdated_reason = "positioning errored"
                  MarkerPosition::File.instance
                else
                  T.absurd(positioning)
                end
              end
            end

            (result[thread.path] ||= []) << ThreadSummary.new(
              id: thread.id,
              outdated_reason: outdated_reason,
              position:,
            )
          end
        else
          # Positioning currently depends on loading the full diff, which
          # interferes with the diff contents loader.
          diff = diff.dup

          line_threads = threads.select(&:on_line?)
          file_threads = threads.select(&:on_file?)

          file_threads.each do |thread|
            result[thread.path] ||= []
            file_thread_outdated = thread.file_level_thread_outdated_as_of_diff?(summary: diff.summary.deltas)
            T.must(result[thread.path]) << ThreadSummary.new(
              id: thread.id,
              outdated_reason: file_thread_outdated ? "outdated" : nil,
              position: MarkerPosition::File.instance,
            )
          end

          Promise.all(line_threads.map do |thread|
            Promise.all([
              thread.async_reposition_from_blob_position(diff),
              thread.async_start_line(diff),
              thread.async_end_line(diff),
              thread.async_current_line(diff, safe: true),
            ]).then do |_, start_line, end_line, current_line|
              if thread.outdated || (start_line.nil? && current_line.nil?)
                # If the thread is outdated, or start_line and current_line are nil
                # then by definition we cannot provide
                # a current line position. Fallback to using the file position.
                position = MarkerPosition::File.instance
              elsif start_line.nil? && current_line
                # If only start_line is nil, then fallback to using current line.
                position = MarkerPosition::Line.right(current_line)
              elsif start_line&.right == end_line&.right
                position = MarkerPosition::Line.from_diff_line(start_line)
              else
                position = MarkerPosition::LineRange.from_diff_lines(start_line, end_line)
              end

              result[thread.path] ||= []
              T.must(result[thread.path]) << ThreadSummary.new(
                id: thread.id,
                outdated_reason: thread.outdated? ? "outdated" : nil,
                position:,
              )
            end
          end).sync
        end

        result
      end
    end

    sig { params(paths: T::Array[String]).returns(T.nilable(PullRequests::PageData::Codeowners::Loader::Data)) }
    def load_codeowners_data(paths)
      return unless @include_codeowners

      PullRequests::PageData::Codeowners::Loader.load(
        viewer: @current_user,
        paths: paths,
        refname: @comparison.diff.base_sha,
        repository: T.must(@pull_request.base_repository),
      )
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
