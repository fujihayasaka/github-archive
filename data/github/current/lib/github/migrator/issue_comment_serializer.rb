# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueCommentSerializer < BaseSerializer
      def scope
        IssueComment.preload(:user, :reactions, issue: :pull_request)
      end

      def as_json(options = {})
        hash = {
          type: "issue_comment",
          url: url,
        }

        if pull_request
          hash[:pull_request] = pull_request
        else
          hash[:issue] = issue
        end

        hash.merge!({
          user: user,
          body: body,
          formatter: formatter,
          reactions: reactions,
          created_at: created_at,
        })

        hash
      end

      private

      def issue
        url_for_model(model.issue)
      end

      def pull_request
        url_for_model(model.issue.pull_request)
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
    end
  end
end
