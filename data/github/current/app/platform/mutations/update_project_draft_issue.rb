# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectDraftIssue < Platform::Mutations::Base
      description "Updates a draft issue within a Project."
      minimum_accepted_scopes ["write:org", "repo"]

      mobile_only true

      argument :draft_issue_id, ID, "The ID of the draft issue to update.", required: true, loads: Objects::DraftIssue

      argument :title, String, "The title of the draft issue.", required: false
      argument :body, String, "The body of the draft issue.", required: false
      argument :assignee_ids, [ID], "The IDs of the assignees of the draft issue.", required: false, loads: Objects::User, as: :assignees

      field :draft_issue, Objects::DraftIssue, "The draft issue updated in the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        inputs[:draft_issue].async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            permission.access_allowed?(
              :project_next_write,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(draft_issue:, **inputs)
        if draft_issue.memex_project.deleted_at.present?
          raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{draft_issue.memex_project.global_relay_id}'."
        end

        draft_issue.title = inputs[:title] if inputs.key?(:title)
        draft_issue.body = inputs[:body] if inputs.key?(:body)
        draft_issue.assignees = inputs[:assignees] || [] if inputs.key?(:assignees)

        return { draft_issue: draft_issue } if draft_issue.save

        raise Errors::Unprocessable.new(draft_issue.errors.full_messages.join(", "))
      end
    end
  end
end
