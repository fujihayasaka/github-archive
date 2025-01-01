# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module RepositoryDiscussionAuthor
      include Platform::Interfaces::Base

      description "Represents an author of discussions in repositories."

      field :repository_discussions, Connections.define(Platform::Objects::Discussion),
          description: "Discussions this user has started.", null: false, connection: true do
        argument :order_by, Inputs::DiscussionOrder,
          "Ordering options for discussions returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
        argument :repository_id, ID, "Filter discussions to only those in a specific repository.",
          required: false
        argument :answered, Boolean, "Filter discussions to only those that have been answered " \
          "or not. Defaults to including both answered and unanswered discussions.", required: false,
          default_value: nil
        argument :states,
          [Enums::DiscussionState],
          description: "A list of states to filter the discussions by.",
          default_value: [],
          required: false
      end

      def repository_discussions(order_by: nil, repository_id: nil, answered: nil, states:)
        scope = ::Discussion.authored_by(@object).filter_spam_for(@context[:viewer])
        stat_name = "discussion_author.discussions_enabled_check.dist.time"

        if states.present?
          scope = scope.where(state: states)
        end

        if order_by
          field = order_by[:field]
          direction = order_by[:direction]
          scope = scope.order("discussions.#{field} #{direction}")
        end

        if answered == false
          scope = scope.unanswered
        elsif answered
          scope = scope.answered
        end

        if repository_id
          Helpers::NodeIdentification.async_typed_object_from_id(
            [Objects::Repository], repository_id, @context
          ).then do |repo|
            GitHub.dogstats.distribution_time(stat_name, tags: ["num_repos:1"]) do
              repo.discussions_on? ? scope.for_repository(repo) : ::Discussion.none
            end
          end
        else
          repository_ids_with_authored_discussions = Discussion.
            authored_by(@object).
            distinct.
            pluck(:repository_id)

          repos = @context[:permission].
            filtered_permissible_repository_scope(@object, repository_ids_with_authored_discussions, resource: "discussions").active

          GitHub.dogstats.distribution_time(stat_name, tags: ["num_repos:#{repos.length}"]) do
            repository_id_promises = repos.map do |repo|
              repo.async_discussions_on?.then do |discussions_on|
                discussions_on ? repo.id : nil
              end
            end

            Promise.all(repository_id_promises).then do |filtered_repo_ids|
              scope.where(repository_id: filtered_repo_ids.compact)
            end
          end
        end
      end
    end
  end
end
