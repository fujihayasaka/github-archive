# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class PullRequestReviewSerializer < BaseSerializer
      def scope
        PullRequestReview.preload(:pull_request, :user)
      end

      def as_json(options = {})
        {
          type: "pull_request_review",
          url: url,
          pull_request: pull_request,
          user: user,
          body: body,
          head_sha: head_sha,
          formatter: formatter,
          state: state,
          reactions: reactions,
          created_at: created_at,
          submitted_at: submitted_at,
        }
      end

      private

      def pull_request
        url_for_model(model.pull_request)
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

      def head_sha
        model.head_sha
      end

      def state
        model.state
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

      def submitted_at
        time(model.submitted_at)
      end
    end
  end
end
