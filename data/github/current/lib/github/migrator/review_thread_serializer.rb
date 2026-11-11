# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReviewThreadSerializer < BaseSerializer
      def scope
        PullRequestReviewThread.preload(:pull_request_review, :pull_request, :resolver)
      end

      def as_json(options = {})
        {
          type:                  "pull_request_review_thread",
          url:                        url,
          pull_request:               pull_request,
          pull_request_review:        pull_request_review,
          diff_hunk:                  diff_hunk,
          path:                       path,
          position:                   position,
          original_position:          original_position,
          commit_id:                  commit_id,
          original_commit_id:         original_commit_id,
          start_position_offset:      start_position_offset,
          blob_position:              blob_position,
          start_line:                 start_line,
          line:                       line,
          start_side:                 start_side,
          side:                       side,
          original_start_line:        original_start_line,
          original_line:              original_line,
          created_at:                 created_at,
          resolved_at:                resolved_at,
          resolver:                   resolver,
          subject_type:               subject_type,
          outdated:                   outdated,
        }
      end

      private

      def pull_request
        url_for_model(model.pull_request)
      end

      def pull_request_review
        url_for_model(model.pull_request_review)
      end

      def diff_hunk
        model.diff_hunk
      end

      def path
        model.path
      end

      def position
        model.position
      end

      def original_position
        model.original_position
      end

      def commit_id
        model.commit_id
      end

      def original_commit_id
        model.original_commit_id
      end

      def start_position_offset
        model.start_position_offset
      end

      def blob_position
        model.blob_position
      end

      def start_line
        model.start_line_number
      end

      def line
        model.line
      end

      def start_side
        model.start_side
      end

      def side
        model.side
      end

      def original_start_line
        model.original_start_line
      end

      def original_line
        model.original_line
      end

      def resolved_at
        time(model.resolved_at)
      end

      def resolver
        url_for_model(model.resolver)
      end

      def subject_type
        model.subject_type
      end

      def outdated
        model.outdated
      end
    end
  end
end
