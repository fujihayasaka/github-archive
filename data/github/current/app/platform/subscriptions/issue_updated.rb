# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Subscriptions
    class IssueUpdated < Platform::Subscriptions::Base
      argument :id, ID, required: true, description: "ID of the issue to subscribe to."

      field :deleted_comment_id, ID, null: true, description: "The deleted comment id."
      field :comment_updated, ::Platform::Objects::IssueComment, null: true, description: "The updated comment."

      field :issue_body_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated body."
      field :issue_metadata_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated meta data."
      field :issue_state_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated state."
      field :issue_timeline_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated timeline."
      field :issue_title_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated title."
      field :issue_transfer_state_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated transfer state"
      field :issue_type_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated issue type."
      field :issue_reaction_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated reaction."
      field :comment_reaction_updated, ::Platform::Objects::IssueComment, null: true, description: "The issue comment with the updated reaction."
      field :parent_issue_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated parent issue"
      field :sub_issues_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated sub-issues"
      field :sub_issues_summary_updated, ::Platform::Objects::Issue, null: true, description: "The issue with the updated sub-issues summary. `subIssuesSummary` updates independently of the `subIssues` list (asynchronously), so emits a separate event."

      field :issue, ::Platform::Objects::Issue, null: false, description: "The issue where the subscription is on."
      attr_reader :issue

      def authorized?(**args)
        super
        # id is a required argument so should always be present, but it used to be scope and there may temporarily be
        # clients who haven't transitioned. This can probably be removed in a followup PR:
        id = args[:id] || context[:scope]
        # If the viewer can load the underlying root object (the issue),
        # they should be able to receive the subscription because we're
        # relying on the authz checks called as part of the object lookup
        @issue = Helpers::NodeIdentification.typed_object_from_id([Objects::Issue], id, context)
      rescue Platform::Errors::NotFound
        GitHub.dogstats.increment("graphql_subscriptions.unauthorized", tags: ["event:#{stats_event_name}"])
        raise GraphQL::ExecutionError, "Subscription halted"
      end

      def get_payload
        {
          issue: issue,
          deleted_comment_id: nil,
          issue_body_updated: nil,
          issue_metadata_updated: nil,
          issue_state_updated: nil,
          issue_timeline_updated: nil,
          issue_title_updated: nil,
          issue_reaction_updated: nil,
          issue_transfer_state_updated: nil,
          issue_type_updated: nil,
          comment_reaction_updated: nil,
          comment_updated: nil,
          sub_issues_updated: nil,
          sub_issues_summary_updated: nil,
          parent_issue_updated: nil
        }
      end

      def subscribe(**args)
        get_payload
      end

      def update(**args)
        payload = get_payload
        if context[:scope_object]
          if context[:scope_object][:deleted_comment_id]
            payload[:deleted_comment_id] = context[:scope_object][:deleted_comment_id]
          elsif context[:scope_object][:reacted_comment_id]
            payload[:comment_reaction_updated] = Helpers::NodeIdentification.typed_object_from_id(
              [Objects::IssueComment],
              context[:scope_object][:reacted_comment_id],
              context
            )
          elsif context[:scope_object][:comment_updated_id]
            payload[:comment_updated] = Helpers::NodeIdentification.typed_object_from_id(
              [Objects::IssueComment],
              context[:scope_object][:comment_updated_id],
              context
            )
          else
            payload.each do |obj|
              key = obj[0]
              if context[:scope_object][key]
                payload[key] = issue
              end
            end
          end
        end
        payload
      end
    end
  end
end
