# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddComment < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Adds a comment to an Issue or Pull Request."

      minimum_accepted_scopes ["public_repo"]

      argument :subject_id, ID, "The Node ID of the subject to modify.", required: true, loads: Unions::IssueOrPullRequest, as: :object
      argument :body, String, "The contents of the comment.", required: true

      field :comment_edge, Objects::IssueComment.edge_type, "The edge from the subject's comment connection.", null: true

      field :timeline_edge, Unions::IssueTimelineItem.edge_type, "The edge from the subject's timeline connection.", null: true

      field :subject, Platform::Interfaces::Node, "The subject", null: true

      extras [:lookahead]

      # This mutation can safely read arguments from replicas
      read_arguments_from_replicas!

      read_mutation_fields_from_replicas!(ApplicationRecord::Repositories, ApplicationRecord::Collab)

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, object:, **inputs)
        issueish = if object.is_a?(::PullRequest)
          object.issue
        else
          object
        end
        permission.async_repo_and_org_owner(issueish).then do |repo, org|
          permission.access_allowed?(:create_issue_comment, repo: repo, resource: issueish, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(lookahead:, object:, **inputs)
        replica_clusters = GitHub.flipper[:issue_comments_api_use_collab_replica].enabled? ? [ApplicationRecord::Repositories, ApplicationRecord::Collab] : [ApplicationRecord::Repositories]
        read_from_selected_replicas(replica_clusters) do
          commentable_object = if object.is_a?(::PullRequest)
            object.issue
          else
            object
          end

          repo = object.repository

          integration = context[:integration] if context[:permission].integration_user_request? || context[:permission].integration_bot_request?
          context[:permission].authorize_content(:issue_comment, :create, issue: commentable_object, repo: repo)
          comment = commentable_object.create_comment(context[:viewer], inputs[:body], performed_via_integration: integration)
          if comment.persisted?
            return_payload(lookahead, object, commentable_object, comment)
          else
            raise Errors::Unprocessable.new(comment.errors.full_messages.join(", "))
          end
        end
      end

      def return_payload(lookahead, object, commentable_object, comment)
        comment_relation = commentable_object.comments.filter_spam_for(context[:viewer])
        comment_connection = Platform::ConnectionWrappers::Relation.new(comment_relation, context: context)
        comment_edge = GraphQL::Pagination::Connection::Edge.new(comment, comment_connection)

        result = { subject: object, comment_edge: comment_edge }

        if lookahead.selects?(:timeline_edge)
          timeline = ArrayWrapper.new(object.timeline_for(context[:viewer]))
          timeline_connection = Platform::ConnectionWrappers::ArrayWrapper.new(timeline, context: context)
          result[:timeline_edge] = GraphQL::Pagination::Connection::Edge.new(comment, timeline_connection)
        end

        result
      end
    end
  end
end
