# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SuggestedAssignees < Platform::Resolvers::Users
      argument :query, String, "If provided, searches users by login or profile name", required: false

      def resolve(**arguments)
        query = arguments[:query]

        object.async_user.then do
          if query.present?
            filtered_assignees(query: query)
          else
            participants
          end
        end
      end

      private

      # We don't need to wrap this with `filter_spam` because the spammy check
      # is already included as part of the filter call.
      def filtered_assignees(query:)
        if object.is_a?(PullRequest)
          object.async_issue.then do |issue|
            Promise.all([issue.async_user, issue.async_repository.then(:async_owner)]).then do
              ArrayWrapper.new(issue.filtered_assignees_list(context[:viewer], query))
            end
          end
        else
          ArrayWrapper.new(object.filtered_assignees_list(context[:viewer], query))
        end
      end

      def participants
        object.async_commenters.then do
          if object.is_a?(PullRequest)
            pr_participant_promises = [
              object.async_issue,
              object.async_base_repository,
              object.async_changed_commits,
            ]

            Promise.all(pr_participant_promises).then do
              filter_spam(ArrayWrapper.new(object.participants))
            end
          else
            filter_spam(ArrayWrapper.new(object.participants))
          end
        end
      end
    end
  end
end
