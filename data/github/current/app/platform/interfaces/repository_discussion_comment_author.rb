# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module RepositoryDiscussionCommentAuthor
      include Platform::Interfaces::Base

      description "Represents an author of discussion comments in repositories."

      field :repository_discussion_comments, Connections.define(Platform::Objects::DiscussionComment),
          description: "Discussion comments this user has authored.", null: false, connection: true do
        argument :order_by, Inputs::DiscussionCommentOrder,
          "Ordering options for discussions returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
        argument :repository_id, ID, "Filter discussion comments to only those in a specific repository.",
          required: false
        argument :only_answers, Boolean, "Filter discussion comments to only those that were marked as the answer", default_value: false, required: false
      end

      def repository_discussion_comments(order_by: nil, repository_id: nil, only_answers: false)
        scope = DiscussionComment.preload(:user).filter_spam_for(@context[:viewer])
        stat_name = "discussion_comment_author.discussions_enabled_check.dist.time"

        if only_answers
          scope = scope.chosen_answers
        end

        if order_by
          field = order_by[:field]
          direction = order_by[:direction]
          scope = scope.order(field => direction)
        end

        if repository_id
          Helpers::NodeIdentification.async_typed_object_from_id(
            [Objects::Repository], repository_id, @context
          ).then do |repo|
            GitHub.dogstats.distribution_time(stat_name, tags: ["num_repos:1"]) do
              repo.discussions_on? ? scope.for_repository(repo) : DiscussionComment.none
            end
          end
        else
          repository_ids_with_authored_discussion_comments = DiscussionComment.
            where(user_id: @object.id).
            distinct.
            pluck(:repository_id)

          repos = @context[:permission].
            filtered_permissible_repository_scope(@object, repository_ids_with_authored_discussion_comments, resource: "discussions")

          GitHub.dogstats.distribution_time(stat_name, tags: ["num_repos:#{repos.length}"]) do
            repository_id_promises = repos.map do |repo|
              repo.async_discussions_on?.then do |discussions_on|
                discussions_on ? repo.id : nil
              end
            end

            Promise.all(repository_id_promises).then do |filtered_repo_ids|
              scope.where(user_id: @object.id, repository_id: filtered_repo_ids.compact)
            end
          end
        end
      end
    end
  end
end
