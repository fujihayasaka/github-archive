# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReviewCommentImporter < GitHub::Migrator::Importer

      INVALID_FILE_DIFF_REGEX = /\A@@\s-\d+,\d+\s[+]{1}\d+(|,\d+)\s@@\z/i

      def initialize(options = {})
        super
        @in_reply_to_map = {}
      end

      def import(attributes, options = {})
        comment = PullRequestReviewComment.new do |review_comment|
          review_comment.in_reply_to = model_from_source_url(attributes["in_reply_to"])
          review_comment.pull_request_review = model_from_source_url(attributes["pull_request_review"])
          pull_request = model_from_source_url!(attributes["pull_request"])

          if review_comment.in_reply_to
            review_comment.pull_request_review_thread_id = review_comment.in_reply_to&.pull_request_review_thread_id
          else
            review_thread = initialize_review_thread(pull_request.id, review_comment.pull_request_review&.id)
            review_thread.diff_hunk = attributes["diff_hunk"]
            review_thread.path = attributes["path"]
            review_thread.position = attributes["position"]
            review_thread.original_position = attributes["original_position"]
            review_thread.commit_id = attributes["commit_id"]
            review_thread.original_commit_id = attributes["original_commit_id"]
            review_thread.subject_type = attributes["subject_type"]

            import_model(review_thread).tap do |review_thread|
              recalculate_position_with_retries(review_thread) unless attributes["position"]
              review_comment.pull_request_review_thread_id = review_thread.id
            end
          end

          review_comment.pull_request = pull_request
          review_comment.repository = pull_request.repository
          review_comment.user = user_or_fallback(attributes["user"])
          review_comment.body = attributes["body"]
          review_comment.formatter = attributes["formatter"]
          # I know we're not supposed to set state directly, but we don't need
          # events fired for the comment when importing
          review_comment.send(:state=, attributes["state"])
          review_comment.created_at = attributes["created_at"]
        end

        ImporterResult.new(
          import_model(comment)
        )
      rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a PullRequestReviewComment::AbstractPositionData::InvalidDiffError",
          "pull_request_review_comment",
          "skipped"
        )
      rescue PullRequestReviewComment::AbstractPositionData::InvalidPathError => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a PullRequestReviewComment::AbstractPositionData::InvalidPathError",
          "pull_request_review_comment",
          "skipped"
        )
      rescue GitRPC::Timeout => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a GitRPC::Timeout",
          "pull_request_review_comment",
          "skipped"
        )
      rescue GitRPC::Failure => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a GitRPC::Failure",
          "pull_request_review_comment",
          "skipped"
        )
      rescue GitRPC::ObjectMissing => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a GitRPC::ObjectMissing",
          "pull_request_review_comment",
          "skipped"
        )
      rescue ActiveModel::RangeError => error
        # TODO: Remove this check and method once archive metadata validation
        # is implemented. See https://github.com/github/data-liberation/issues/344
        if should_log_and_skip?(attributes)
          log_and_create_importer_result(
            attributes,
            error,
            "Skipped import: Invalid file diff comment",
            "pull_request_review_comment",
            "skipped"
          )
        else
          raise error
        end
      end

      private

      def recalculate_position_with_retries(thread)
        attempt = 1
        begin
          recalculate_position(thread)
        rescue GitRPC::Failure
          raise if attempt >= 5
          attempt += 1
          retry
        end
      end

      def recalculate_position(thread)
        thread.send(:ensure_synced_with_pull)
      end

      def initialize_review_thread(pull_request_id, pull_request_review_id)
        PullRequestReviewThread.new(
          pull_request_id:        pull_request_id,
          pull_request_review_id: pull_request_review_id,
        )
      end

      # Check to see if we have an invalid file diff comment from
      # an earlier version of GHES
      def invalid_file_diff?(diff)
        !!(diff =~ INVALID_FILE_DIFF_REGEX)
      end

      def should_log_and_skip?(attributes)
        invalid_file_diff?(attributes["diff_hunk"]) &&
          nil_or_zero?(attributes["position"]) &&
          nil_or_zero?(attributes["original_position"])
      end

      def nil_or_zero?(value)
        value.to_i.zero?
      end
    end
  end
end
