# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Loader
    include GitHub::ResilienceMixin

    # Taken from PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES
    MAX_CONTEXT_LINES = 3

    class DiffSide < T::Enum
      enums do
        RIGHT = new("RIGHT")
        LEFT = new("LEFT")
      end
    end

    class ThreadSubject < T::Struct
      const :diff_lines, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
      const :end_line, T.nilable(Numeric)
      const :end_diff_side, T.nilable(DiffSide)
      const :original_end_line, T.nilable(Numeric)
      const :original_start_line, T.nilable(Numeric)
      const :pull_request_commit, T.nilable(String)
      const :start_diff_side, T.nilable(DiffSide)
      const :start_line, T.nilable(Numeric)
    end

    class ThreadPreview < T::Struct
      const :first_comment, T.nilable(T::Array[PullRequests::PageData::ThreadComments::Loader::Comment])
      const :line, T.nilable(Numeric)
      const :id, String
      const :is_outdated, T::Boolean
      const :is_resolved, T::Boolean
      const :path, String
      const :subject, ThreadSubject
      const :subject_type, String
      const :thread_comments, T::Array[PullRequestReviewComment]
      const :original_diff_path_uri, T.nilable(String)
    end

    class ThreadCounts < T::Struct
      const :path, String
      const :thread_count, Integer
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter)
      ).returns(T::Array[ThreadPreview])
    end
    def self.load(current_user:, pull_request:, limit_config:, cap_filter: nil)
      new(current_user:, pull_request:, limit_config:, cap_filter:).load
    end

    sig do params(
      current_user: T.nilable(User),
      pull_request: PullRequest,
      limit_config: PullRequests::PageData::Files::PageLimitConfig,
      cap_filter: T.nilable(ConditionalAccess::Web::Filter)
    ).void
    end
    def initialize(current_user:, pull_request:, limit_config:, cap_filter: nil)
      @current_user = current_user
      @pull_request = pull_request
      @limit_config = limit_config
      @cap_filter = cap_filter
    end

    sig { returns(T::Array[ThreadPreview]) }
    def load
      with_database_error_fallback(fallback: []) do
        threads = @limit_config.apply_page_limit(
          PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads
        ) do |limit|
          @pull_request.review_threads.visible_to(current_user).limit(limit)
        end

        repository = T.must(@pull_request.repository)

        if FeatureFlag.vexi.enabled?(:prx_comment_outside_the_diff, repository, repository.owner, default: false)
          comments_by_thread_id = PullRequests::PageData::ThreadComments::Loader.load(
            threads: threads,
            current_user: current_user,
            max_comments: 1,
            cap_filter: cap_filter,
            comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Preview
          )

          use_otd_context_lines = repository.feature_flag_enabled?(:cotd_thread_preview_context_lines, default: false)

          if use_otd_context_lines
            GitHub::PrefillAssociations.prefill_batch_method(threads, :prelude_diff_lines_outside_diff, @pull_request, MAX_CONTEXT_LINES)
          end

          batched_data = threads.each_with_object({}) do |thread, hash|
            # Attempt to reduce diff round trips by reusing our original positioning.
            if original_positioning = thread.original_positioning
              case original_positioning
              when PullRequests::CommentPosition::Positions::Line
                original_start_line = original_positioning.line
                original_end_line = original_positioning.line
                original_path = original_positioning.path
              when PullRequests::CommentPosition::Positions::Multiline
                original_start_line = original_positioning.start_line
                original_end_line = original_positioning.end_line
                original_path = original_positioning.end_path
              when PullRequests::CommentPosition::Positions::File
                original_start_line = nil
                original_end_line = nil
                original_path = original_positioning.path
              else
                original_start_line = nil
                original_end_line = nil
                original_path = nil
              end
            end

            diff_lines = if use_otd_context_lines
              Promise.resolve(thread.prelude_diff_lines_outside_diff(@pull_request, MAX_CONTEXT_LINES))
            else
              thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES)
            end

            hash[thread] = {
              diff_lines:,
              original_end_line: original_end_line ? Promise.resolve(original_end_line) : thread.async_original_line,
              original_start_line: original_start_line ? Promise.resolve(original_start_line) : thread.async_original_start_line,
              review_comments: thread.async_review_comments_for(@current_user),
            }
          end

          Promise.all([pull_request.async_path_uri] + batched_data.values.flat_map(&:values)).sync

          pull_request_path_uri = pull_request.async_path_uri.sync

          threads_and_positions = PullRequests::CommentPosition.from_pull_request_threads(
            pull_request: @pull_request,
            threads: threads.to_a,
            destination_base_commit_oid: @pull_request.base_sha,
            destination_head_commit_oid: @pull_request.head_sha,
            position_only: true, # Reduce GitRPC traffic as much as we can!
          )

          threads_and_positions.map do |thread, value|
            is_outdated = false

            if value.is_a?(PullRequests::CommentPosition::Errors)
              is_outdated = true
            else
              case position = value.positioning
              when PullRequests::CommentPosition::Positions::Line
                path = position.path
                line = position.line
                commit_oid = position.commit_oid
                start_line = line
                start_commit_oid = start_commit_oid
              when PullRequests::CommentPosition::Positions::Multiline
                path = position.end_path
                line = position.end_line
                commit_oid = position.end_commit_oid
                start_line = position.start_line
                start_commit_oid = position.start_commit_oid
              when PullRequests::CommentPosition::Positions::File
                path = position.path
                commit_oid = position.commit_oid
                start_commit_oid = position.commit_oid
              when PullRequests::CommentPosition::Positions::Indeterminate, PullRequests::CommentPosition::Positions::Errored
                is_outdated = true
              end
            end

            thread_comments = (batched_data.dig(thread, :review_comments)&.sync || []).sort_by(&:id)

            if thread.outdated
              path_uri = pull_request_path_uri.dup
              path_uri.path += "/files/#{thread.original_commit_id}"

              if id = thread_comments.first&.id
                path_uri.fragment = "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{id}"
              end

              original_diff_path_uri = path_uri.to_s
            end

            ThreadPreview.new(
              id: thread.id.to_s,
              first_comment: comments_by_thread_id[thread.id],
              line:,
              is_outdated:,
              is_resolved: thread.resolved?,
              path: thread.path,
              subject_type: thread.subject_type,
              subject: ThreadSubject.new(
                diff_lines: batched_data.dig(thread, :diff_lines).sync,
                end_line: line,
                end_diff_side: commit_oid == position&.base_commit_oid ? DiffSide::LEFT : DiffSide::RIGHT,
                original_end_line: batched_data.dig(thread, :original_end_line)&.sync,
                original_start_line: batched_data.dig(thread, :original_start_line)&.sync,
                pull_request_commit: commit_oid,
                start_diff_side: start_commit_oid == position&.base_commit_oid ? DiffSide::LEFT : DiffSide::RIGHT,
                start_line: start_line || line, # This always has a value, even if there isn't a range.
              ),
              thread_comments:,
              original_diff_path_uri:
            )
          end
        else
          comments_by_thread_id = PullRequests::PageData::ThreadComments::Loader.load(
            threads: threads,
            current_user: current_user,
            max_comments: 1,
            cap_filter: cap_filter,
            comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Preview
          )

          promises = threads.map do |thread|
            thread_data = {
              diff_lines: thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES),
              end_side: thread.async_diff_side,
              end_line: thread.async_end_line,
              line: thread.async_line,
              original_diff_path_uri: thread.outdated? ? thread.async_original_diff_path_uri : Promise.resolve(nil),
              original_end_line: thread.async_original_line,
              original_start_line: thread.async_original_start_line,
              review_comments: thread.async_review_comments_for(@current_user),
              start_line: thread.async_start_line,
              start_side: thread.async_start_side,
            }

            Promise.all(thread_data.values).then do
              ThreadPreview.new(
                first_comment: comments_by_thread_id[thread.id],
                line: thread_data[:line].sync,
                id: String(thread.id),
                is_outdated: thread.outdated?,
                is_resolved: thread.resolved?,
                path: thread.path,
                subject_type: thread.subject_type,
                subject: ThreadSubject.new(
                  diff_lines: thread_data[:diff_lines].sync,
                  end_line: thread_data[:end_line].sync&.position,
                  end_diff_side: thread_data[:end_side].sync == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                  original_end_line: thread_data[:original_end_line].sync,
                  original_start_line: thread_data[:original_start_line].sync,
                  pull_request_commit: thread.commit_id,
                  start_diff_side: thread_data[:start_side].sync == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                  start_line: thread_data[:start_line].sync&.position
                ),
                thread_comments: thread_data[:review_comments].sync,
                original_diff_path_uri: thread_data[:original_diff_path_uri].sync&.to_s
              )
            end
          end

          Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end
    end
  end
end
