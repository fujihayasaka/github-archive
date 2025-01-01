# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2DraftIssue < Platform::Mutations::Base
      description "Updates a draft issue within a Project."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :draft_issue_id, ID, "The ID of the draft issue to update.", required: true, loads: Objects::DraftIssue

      argument :title, String, "The title of the draft issue.", required: false
      argument :body, String, "The body of the draft issue.", required: false
      argument :assignee_ids, [ID], "The IDs of the assignees of the draft issue.", required: false, loads: Objects::User

      field :draft_issue, Objects::DraftIssue, "The draft issue updated in the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        inputs[:draft_issue].async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            permission.access_allowed?(
              :project_v2_write,
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

        if inputs.key?(:title)
          title_value = inputs[:title]
          denormalize_title_value(draft_issue, title_value)
        end

        draft_issue.title = inputs[:title] if inputs.key?(:title)
        draft_issue.body = inputs[:body] if inputs.key?(:body)
        draft_issue.assignees = inputs[:assignees] || [] if inputs.key?(:assignees)

        if draft_issue.save
          { draft_issue: draft_issue }
        else
          raise Errors::Unprocessable.new(draft_issue.errors.full_messages.join(", "))
        end
      end

      #
      # Denormalize the new draft issue title onto the `MemexProjectColumnValue`` table for the related project.
      #
      # This ensures a user flagged into the `memex_read_denormalized_title` feature flag will see the correct
      # value, instead of the wrong cached value.
      #
      private def denormalize_title_value(draft_issue, title_value)
        return unless title_value.present?

        title_column = draft_issue.memex_project.find_column_by_name_or_id("Title")
        return unless title_column

        success = draft_issue.memex_project_item.set_column_value(title_column, { title: title_value },  @context[:viewer])
        unless success
          raise Errors::Unprocessable.new("Could not update title of draft issue with global id of '#{draft_issue.global_relay_id}'.")
        end
      end
    end
  end
end
