# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueSerializer < BaseSerializer
      def scope
        Issue.preload(included_issue_associations)
      end

      def as_json(options = {})
        {
          type: "issue",
          url: url,
          repository: repository,
          user: user,
          title: title,
          body: body,
          assignee: assignee,
          assignees: assignees,
          milestone: milestone,
          labels: labels,
          reactions: reactions,
          closed_at: closed_at,
          created_at: created_at,
          updated_at: updated_at,
        }
      end

      private

      def included_issue_associations
        [:repository, :user, :assignee, :assignees, :milestone, :labels, :reactions]
      end

      def issue
        model
      end

      def repository
        url_for_model(issue.repository)
      end

      def user
        url_for_model(issue.user)
      end

      def title
        issue.title
      end

      def body
        issue.body
      end

      def assignee
        assignees.first
      end

      def assignees
        issue.assignees.map do |assignee|
          url_for_model(assignee)
        end
      end

      def milestone
        if milestone = issue.milestone
          url_for_model(milestone)
        end
      end

      def labels
        issue.labels.map do |label|
          url_for_model(label)
        end
      end

      def reactions
        issue.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: reaction.subject_type,
            created_at: reaction.created_at
          }
        end
      end

      def closed_at
        time(issue.closed_at)
      end

    end
  end
end
