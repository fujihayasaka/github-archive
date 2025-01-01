# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReviewCommentSerializer < BaseSerializer
      def as_json(options = {})
        {
          type:                       "pull_request_review_comment",
          url:                        url,
          pull_request:               pull_request,
          pull_request_review:        pull_request_review,
          pull_request_review_thread: pull_request_review_thread,
          user:                       user,
          body:                       body,
          formatter:                  formatter,
          diff_hunk:                  diff_hunk,
          path:                       path,
          position:                   position,
          original_position:          original_position,
          commit_id:                  commit_id,
          original_commit_id:         original_commit_id,
          state:                      state,
          in_reply_to:                in_reply_to,
          reactions:                  reactions,
          created_at:                 created_at,
          subject_type:               subject_type,
        }
      end

      private

      def pull_request
        url_for_model(model.pull_request)
      end

      def pull_request_review
        url_for_model(model.pull_request_review)
      end

      def pull_request_review_thread
        url_for_model(model.pull_request_review_thread)
      end

      def user
        url_for_model(model.user)
      end

      def body
        model.body
      end

      def formatter
        model.formatter
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

      def state
        PullRequestReviewComment.states[model.state]
      end

      def in_reply_to
        url_for_model(model.in_reply_to)
      end

      def reactions
        model.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: reaction.subject_type,
            created_at: reaction.created_at
          }
        end
      end

      def subject_type
        model.subject_type
      end
    end
  end
end
