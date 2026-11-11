# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      module Services
        # Service object that builds pull request review threads and reply comments
        # for an existing review during an import.
        #
        # Used by both the single-shot ImportPullRequestReviewAPIHandler (which
        # creates the review and all of its threads/comments in one call) and the
        # batched ImportPullRequestReviewThreadsAPIHandler (which appends
        # threads/comments to an already-existing pending review).
        #
        # Construct one instance per request scoped to a specific pull request and
        # review; call #create_thread / #create_reply_comment for each item.
        # Validation failures are signalled by raising Errors::InvalidReviewError
        # so callers can collect or rescue them.
        class PullRequestReviewThreadCreator
          include Imports::Helpers::Attribution
          include Imports::Helpers::ContentCreation

          # Maps proto review state enum values to ActiveRecord state symbols.
          # Shared by both the single-shot and batched review import handlers so they
          # agree on the proto<->model mapping.
          REVIEW_STATE_MAP = {
            PULL_REQUEST_REVIEW_STATE_PENDING: :pending,
            PULL_REQUEST_REVIEW_STATE_COMMENTED: :commented,
            PULL_REQUEST_REVIEW_STATE_CHANGES_REQUESTED: :changes_requested,
            PULL_REQUEST_REVIEW_STATE_APPROVED: :approved,
            PULL_REQUEST_REVIEW_STATE_DISMISSED: :dismissed
          }.freeze

          DIFF_TYPE_MAP = {
            PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_LEFT: :left,
            PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT: :right
          }.freeze

          SUBJECT_TYPES_MAP = {
            PULL_REQUEST_REVIEW_SUBJECT_TYPE_FILE: :file,
            PULL_REQUEST_REVIEW_SUBJECT_TYPE_LINE: :line
          }.freeze

          RANGE_INFO_REGEX = %r{@@ -\d+(,\d+)? \+(?<modified_start>\d+)(,\d+)? @@}.freeze

          attr_reader :pull_request, :review

          def initialize(pull_request:, review:)
            @pull_request = pull_request
            @review = review
          end

          # Builds a review thread on the configured review. The thread must have at least one comment.
          # The thread can optionally have multiple comments if the reviewer submitted multiple comments on the
          # thread inside the same review.
          def create_thread(thread_data)
            # Build the basic review thread, will update with more data next.
            thread = review.review_threads.build(
              pull_request: pull_request,
              pull_request_review: review
            )

            thread.subject_type = SUBJECT_TYPES_MAP[thread_data.subject_type]

            # Only update the state of the thread (from active to resolved) if the caller passes
            # in resolved data (resolved_by_user_login or resolved_at).
            if thread_data.resolved_by_user_login.present? || thread_data.resolved_at.present?
              # Ghost is allowed for preserving the resolved at data in case of a deleted account/service account, etc.
              resolver_user = user_or_ghost(thread_data.resolved_by_user_login)
              unless resolver_user
                raise Errors::InvalidReviewError, Twirp::Error.not_found(
                  "Thread resolver user not found.",
                  argument: "resolved_by_user_login",
                  value: thread_data.resolved_by_user_login
                )
              end

              unless thread_data.resolved_at
                raise Errors::InvalidReviewError, Twirp::Error.invalid_argument(
                  "must be non-empty when resolved_by_user_login is present",
                  argument: "resolved_at"
                )
              end

              thread.resolver = resolver_user
              thread.resolved_at = thread_data.resolved_at.to_time
            end

            # A thread must have at least one comment to be valid.
            if thread_data.comments.empty?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "comments")
            end

            first_comment = add_first_comment_and_submit(thread, thread_data, thread_data.comments.first)

            # Build any and all replies to the first comment in the thread from the same review.
            thread_data.comments[1..].each do |comment_data|
              create_reply_comment(thread_id: thread.id, reply_to_id: first_comment.id, comment_data: comment_data)
            end

            thread
          end

          # Validate data for comments that are replies to other existing comments on existing threads.
          def validate_reply!(comment_data)
            if comment_data.reply_to_id.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "reply_to_id")
            end
            if comment_data.reply_to_id && !comment_data.reply_to_id.value.positive?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be positive integer", argument: "reply_to_id")
            end
            if comment_data.thread_id.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "thread_id")
            end
            if comment_data.thread_id && !comment_data.thread_id.value.positive?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be positive integer", argument: "thread_id")
            end
          end

          # Builds a comment that is in reply to a thread (i.e. the first comment in the thread).
          def create_reply_comment(thread_id:, reply_to_id:, comment_data:)
            if comment_data.body.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "body")
            end
            if comment_data.created_at.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
            end

            # Ghost is allowed for preserving the comment data in case of a deleted account/service account, etc.
            comment_user = user_or_ghost(comment_data.user_login)
            unless comment_user
              raise Errors::InvalidReviewError, Twirp::Error.not_found("Comment user not found.", argument: "user_login", value: comment_data.user_login)
            end

            comment = ImportablePullRequestReviewComment.new(
              pull_request: pull_request,
              pull_request_review: review,
              pull_request_review_thread_id: thread_id,
              reply_to_id: reply_to_id,
              user: comment_user,
              body: comment_data.body,
              created_at: comment_data.created_at.to_time
            )

            # .submit! also saves the comment
            rate_limited_mode(comment) do
              comment.submit!
            end

            comment
          end

          private

          # Adds the first comment to the (already-built) thread and submits
          # it. Calling comment.submit! persists the comment, the review, and
          # the thread together. Returns the persisted first comment.
          def add_first_comment_and_submit(thread, thread_data, comment_data)
            # Thread data validations
            if thread_data.created_at.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
            end
            if thread_data.commit_id.empty?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "commit_id")
            end
            if thread_data.path.empty?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "path")
            end
            if !thread_data.diff_hunk && !thread_data.line.positive? && SUBJECT_TYPES_MAP[thread_data.subject_type] == :line
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be positive integer", argument: "line")
            end
            if thread_data.diff_hunk && thread_data.line.negative? && SUBJECT_TYPES_MAP[thread_data.subject_type] == :line
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-negative integer", argument: "line")
            end
            if thread_data.side == :PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_INVALID
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "side")
            end
            if thread_data.start_line && thread_data.start_line.value.negative?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-negative integer", argument: "start_line")
            end
            if thread_data.start_line && thread_data.start_line.value > thread_data.line
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be less than or equal to line", argument: "start_line")
            end
            if thread_data.position && !thread_data.position.value.positive?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be positive integer", argument: "position")
            end
            if thread_data.original_position && !thread_data.original_position.value.positive?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be positive integer", argument: "original_position")
            end

            # Comment data validations
            if comment_data.body.empty?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "body")
            end
            if comment_data.created_at.blank?
              raise Errors::InvalidReviewError, Twirp::Error.invalid_argument("must be non-empty", argument: "created_at")
            end

            # Ghost is allowed for preserving the comment data in case of a deleted account/service account, etc.
            comment_user = user_or_ghost(comment_data.user_login)
            unless comment_user
              raise Errors::InvalidReviewError, Twirp::Error.not_found(
                "Comment user not found.",
                argument: "user_login",
                value: comment_data.user_login
              )
            end

            # The requester can specify a commit range to place the comment if they give a thread_data.base_commit_id different than
            # req.commit_id. If so, start the commit range from thread_data.base_commit_id and end at req.commit_id. Otherwise,
            # we'll just use the merge_base as the start of the commit range.
            start_commit_id = commit_range_present?(thread_data.base_commit_id, thread_data.commit_id) ? thread_data.base_commit_id : pull_request.merge_base

            first_comment_params = {
              thread: thread,
              comment_user: comment_user,
              body: comment_data.body,
              thread_data: thread_data,
              start_commit_id: start_commit_id
            }

            comment = if thread_data.diff_hunk
              build_first_comment_with_diff(**first_comment_params)
            else
              build_first_comment_without_diff(**first_comment_params)
            end

            # These attributes were not exposed in any public methods, so we'll update them now.
            thread.created_at = thread_data.created_at.to_time
            comment.pull_request = pull_request
            comment.pull_request_review = review
            comment.pull_request_review_thread = thread
            comment.created_at = comment_data.created_at.to_time

            begin
              # .submit! saves the comment, review, and thread.
              rate_limited_mode(comment) do
                comment.submit!

                thread.update!(blob_position: thread_data.blob_position&.value) if thread_data.blob_position && thread_data.start_position_offset
              end
            rescue ActiveRecord::RecordInvalid, GitRPC::ObjectMissing => e
              handle_invalid_first_comment(comment, thread_data, e)
            end

            comment
          end

          def commit_range_present?(base_commit_id, commit_id)
            base_commit_id.present? && commit_id != base_commit_id
          end

          # This method handles any cases where submitting (and thus saving) the comment failed.
          def handle_invalid_first_comment(comment, thread_data, error = nil)
            # If the end line (position) is invalid, we have no way to place the comment/thread, so raise.
            if thread_end_line_invalid?(comment.pull_request_review_thread)
              raise Errors::InvalidReviewError, Twirp::Error.malformed("Could not submit review comment: #{comment.errors.full_messages.join(", ")}", octoshift_error_code: "LINE_NOT_FOUND_IN_DIFF")
            end

            # If the start line is invalid (but the end line is valid), we can just place it as a single line thread
            # on the end line.
            if thread_start_line_invalid?(comment.pull_request_review_thread)
              context_message = "_This comment was originally posted from L#{thread_data.start_line&.value}-L#{thread_data.line}_\n\n"
              comment.body = context_message + comment.body
              comment.start_position_data = nil
              rate_limited_mode(comment) do
                comment.save!
              end
              return
            end

            # Check if the error is due to a missing start commit oid.
            if comment.errors.find { |s| s.attribute.to_s == "pull_request_review_thread.start_commit_oid" }
              raise Errors::InvalidReviewError, Twirp::Error.malformed("Could not submit review comment: #{comment.errors.full_messages.join(", ")}", octoshift_error_code: "REVIEW_THREAD_MISSING_START_COMMIT_OID")
            end

            # Check if the error is due to a missing end commit oid.
            if comment.errors.find { |s| s.attribute.to_s == "pull_request_review_thread.end_commit_oid" }
              if FeatureFlag.vexi.enabled_or_raise?(:octoshift_outdated_comment_patch, comment.pull_request.repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
                comment.outdated = true

                rate_limited_mode(comment) do
                  comment.save!
                end

                if comment.valid?
                  rate_limited_mode(comment) do
                    # A comment delegates outdated column to loaded_pull_request_review thread.
                    # Update outdated column on the delegated model with update_column to avoid callbacks and validations.
                    comment.loaded_pull_request_review_thread.update_column(:outdated, thread_data.outdated)
                  end

                  return
                end
              end

              raise Errors::InvalidReviewError, Twirp::Error.malformed("Could not submit review comment: #{comment.errors.full_messages.join(", ")}", octoshift_error_code: "REVIEW_THREAD_MISSING_END_COMMIT_OID")
            end

            if error.is_a?(GitRPC::ObjectMissing)
              raise Errors::InvalidReviewError, Twirp::Error.malformed("Could not submit review comment: #{error}", octoshift_error_code: "REVIEW_THREAD_COMMIT_ID_MISSING")
            end

            # Otherwise, we're not sure so just raise :)
            raise Errors::InvalidReviewError, Twirp::Error.malformed("Could not submit review comment: #{comment.errors.full_messages.join(", ")}", octoshift_error_code: "INVALID_REVIEW_THREAD")
          end

          # A thread can lack a start_position_offset for two reasons:
          #   - It is a single line thread
          #   - It has a start line outside of the diff hunk
          # If it is for a single line, it won't have start_position_data, so if
          # we see a thread with start_position_data but without a
          # start_position_offset, we know that the start line is outside of the
          # diff hunk.
          def thread_start_line_invalid?(thread)
            thread.start_position_offset.nil? && thread.start_position_data
          end

          def thread_end_line_invalid?(thread)
            thread.position.nil?
          end

          # Calculates the review thread position in the diff hunk from the full file's
          # line number.
          def diff_hunk_position(diff_hunk, file_line_number)
            range_info = diff_hunk.match(RANGE_INFO_REGEX)
            modified_start = range_info[:modified_start].to_i - 1 # Skip range info

            file_line_number - modified_start
          end

          def build_first_comment_with_diff(thread:, comment_user:, body:, thread_data:, start_commit_id:)
            diff_hunk = thread_data.diff_hunk.value
            position = thread_data.position&.value
            original_position = thread_data.original_position&.value || diff_hunk_position(diff_hunk, thread_data.line)

            outdated = position.nil?
            if FeatureFlag.vexi.enabled_or_raise?(:octoshift_outdated_comment_patch, pull_request.repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
              outdated = [true, false].include?(thread_data.outdated) ? thread_data.outdated : position.nil?
            end

            thread_attributes = {
              outdated: outdated,
              diff_hunk: diff_hunk,
              path: thread_data.path,
              position: position,
              original_position: original_position,
              original_start_commit_id: start_commit_id,
              original_base_commit_id: pull_request.merge_base,
              subject_type: SUBJECT_TYPES_MAP[thread_data.subject_type]
            }

            # This maintains backward-compatibility for GHES and should be removed once start_position_offset and blob_position are present in all archives.
            if thread_data.start_position_offset || thread_data.blob_position
              thread_attributes[:original_commit_id] = thread_data.commit_id
              thread_attributes[:start_position_offset] = thread_data.start_position_offset&.value
            else
              if outdated
                comparison = get_comparison(start_commit_id, thread_data)
                if defined?(comparison.diffs)
                  diff = comparison.diffs.only_params
                  start_position_data = diff_position_data(diff, thread_data.path, thread_data.start_side, thread_data.start_line)
                  end_position_data = diff_position_data(diff, thread_data.path, thread_data.side, thread_data.line)
                end
              end
              thread_attributes[:commit_id] = thread_data.commit_id
              thread_attributes[:start_position_data] = start_position_data
              thread_attributes[:end_position_data] = end_position_data
            end

            thread.assign_attributes(**thread_attributes)

            review.review_comments.build(
              pull_request: pull_request,
              pull_request_review_thread: thread,
              user: comment_user,
              body: body,
              subject_type: SUBJECT_TYPES_MAP[thread_data.subject_type]
            )
          end

          def build_first_comment_without_diff(thread:, comment_user:, body:, thread_data:, start_commit_id:)
            comparison = get_comparison(start_commit_id, thread_data)

            unless comparison
              raise Errors::InvalidReviewError, Twirp::Error.malformed(
                "Unable to create a comparison for review thread.",
                octoshift_error_code: "UNABLE_TO_COMPARE"
              )
            end

            thread.build_first_comment(
              user: comment_user,
              diff: comparison.diffs.only_params,
              body: body,
              path: thread_data.path,
              line: thread_data.line,
              side: DIFF_TYPE_MAP[thread_data.side],
              start_line: thread_data.start_line&.value,
              start_side: DIFF_TYPE_MAP[thread_data.start_side]
            )
          end

          def get_comparison(start_commit_id, thread_data)
            PullRequest::Comparison.find(
              pull: pull_request,
              start_commit_oid: start_commit_id,
              end_commit_oid: thread_data.commit_id,
              base_commit_oid: pull_request.merge_base
            )
          end

          def diff_position_data(diff, path, side, line)
            # The start line is a google.protobuf.Int64Value type so it could be nil.
            # The end line is an int64 type (non-nullable) so it would be cast from nil to 0 in the Twirp request.
            # Therefore, check if line is nil or 0.
            return nil if line.nil? || line == 0

            PullRequestReviewComment::DiffPositionData.new(
              diff: diff,
              line: line.is_a?(Integer) ? line : line.value,
              right_path: path,
              side: side,
            )
          end
        end
      end
    end
  end
end
