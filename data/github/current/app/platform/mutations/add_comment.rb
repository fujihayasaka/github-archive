# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddComment < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      COPILOT_BOT_ID_DOTCOM = 198982749
      GITHUB_ACTIONS_BOT_ID_DOTCOM = 41898282

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

      sig { returns(T::Array[T.class_of(ApplicationRecord::Base)]) }
      def self.replica_clusters_for_read_mutation_fields_clusters
        clusters = super
        if FeatureFlag.vexi.enabled?(:gql_read_mutation_fields_from_replicas_mysql1, default: false)
          clusters | [ApplicationRecord::Mysql1]
        else
          clusters
        end
      end

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
        read_from_selected_replicas([ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::Mysql1]) do
          commentable_object = if object.is_a?(::PullRequest)
            object.issue
          else
            object
          end

          repo = object.repository

          integration = context[:integration] if context[:permission].integration_user_request? || context[:permission].integration_bot_request?
          context[:permission].authorize_content(:issue_comment, :create, issue: commentable_object, repo: repo)

          # Workaround for installation context switching bug (https://github.com/github/ecosystem-apps/issues/7794)
          # Preserve installation context for Copilot and GitHub Actions bots during cross-reference processing
          is_copilot_bot = copilot_bot?(integration)
          is_actions_bot = context[:viewer].bot? && (
            context[:viewer].id == GITHUB_ACTIONS_BOT_ID_DOTCOM || # Production GitHub Actions bot
            (integration && integration.slug == "github-actions") # Test environment GitHub Actions
          )
          actions_workaround_enabled = is_actions_bot && FeatureFlag.vexi.enabled?(:actions_installation_context_workaround, integration, default: false)

          installation = if is_copilot_bot || actions_workaround_enabled
            if FeatureFlag.vexi.enabled?(:add_comment_use_context_installation, default: false)
              context[:installation]
            else
              context[:viewer].installation
            end
          end

          comment = commentable_object.create_comment(context[:viewer], inputs[:body], performed_via_integration: integration) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          if (is_copilot_bot || actions_workaround_enabled) && context[:viewer].bot?
            context[:viewer].installation = installation
          end

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

      private

      def copilot_bot?(integration)
        if FeatureFlag.vexi.enabled?(:copilot_integration_check_kill_switch, default: false)
          return context[:viewer].bot? && context[:viewer].id == COPILOT_BOT_ID_DOTCOM
        end

        integration.present? && Apps::Privileged.capable?(:is_copilot, app: integration)
      end
    end
  end
end
