# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SuggestedActors < Platform::Resolvers::Users
      include Helpers::AssigneesHelper

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
              ArrayWrapper.new(issue.filtered_assignees_list(viewer, query))
            end
          end
        else
          repo = object.repository
          suggested_assignees = object.filtered_assignees_list(viewer, query)
          async_bots(capabilities, viewer, repo, query: query).then do |bots|
            ArrayWrapper.new(bots + suggested_assignees)
          end
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
            object.async_repository.then do |repo|
              users = object.participants
              async_bots(capabilities, viewer, repo).then do |bots|
                filter_spam(ArrayWrapper.new(bots + users))
              end
            end
          end
        end
      end

      def capabilities
        ["can_be_assigned"]
      end

      def viewer
        context[:viewer]
      end
    end
  end
end
