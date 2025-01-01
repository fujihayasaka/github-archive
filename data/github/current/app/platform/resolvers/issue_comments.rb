# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueComments < Resolvers::Base

      argument :order_by, Inputs::IssueCommentOrder,
        "Ordering options for issue comments returned from the connection.", required: false

      argument :since, Scalars::DateTime, "List issue comments since given date", visibility: :under_development, required: false

      type Connections.define(Objects::IssueComment), null: false

      def resolve(**arguments)
        case object
        when PullRequest
          object.async_issue.then do |issue|
            build_issue_relation(issue, arguments[:since], arguments[:order_by])
          end
        when Issue
          build_issue_relation(object, arguments[:since], arguments[:order_by])
        when User
          return ArrayWrapper.new([]) if object.ghost?

          relation = filter_permissible_repository_resources(object)

          if order_by = arguments[:order_by]
            field = order_by[:field]
            direction = order_by[:direction]
            relation = relation.order(field => direction)
          end

          relation
        end
      end

      private

      def filter_permissible_repository_resources(object)
        relation = object.issue_comments.from("`issue_comments` IGNORE INDEX FOR ORDER BY (PRIMARY)")
        relation = relation.joins(:issue).merge(Issue.filter_spam_for(context[:viewer]))

        # there is no need to filter for spam on the issue comments if the viewer of the query results is the
        # same as the author of the comments requested.
        if context[:viewer]&.id != object.id
          relation = relation.where(user_hidden: false)
        end

        context[:permission].filter_permissible_repository_resources(object, relation, unique_repository_ids_scope:, resource: "issues", filter_spam: true)
      end

      def unique_repository_ids_scope
        scope = Issue.filter_spam_for(context[:viewer])

        issue_comments_repos_scope = object.issue_comments.filter_spam_for(context[:viewer])
        scope = scope.where(repository_id: issue_comments_repos_scope.group(:repository_id).select(:repository_id))

        scope.group(:repository_id).select(:repository_id)
      end

      def build_issue_relation(issue, since, order_by)
        if context[:permission].typed_can_access?("Issue", issue)
          relation = build_filtered_comments_relation(issue)

          relation = relation.since(since) if since

          if order_by
            field = order_by[:field]
            direction = order_by[:direction]
            # reorder to override the scope on issue.comments
            relation = relation.reorder(field => direction)
          end

          relation
        else
          ::IssueComment.none
        end
      end

      def build_filtered_comments_relation(issue)
        comments_scope = issue.comments.
          filter_spam_for(context[:viewer])

        comment_repository_ids = comments_scope.distinct.pluck(:repository_id)

        repo_scope = Repository.
          where(id: comment_repository_ids).
          filter_spam_and_disabled_for(context[:viewer])

        comments_scope.where("issue_comments.repository_id": repo_scope.pluck(:id))
      end
    end
  end
end
