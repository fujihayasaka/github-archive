# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectDraftIssue < Platform::Mutations::Base
      description "Creates a new draft issue and add it to a Project."
      minimum_accepted_scopes ["write:org", "repo"]

      required_capabilities [:mobile_only_schema_mask]

      argument :project_id, ID, "The ID of the Project to add the draft issue to. This field is required.", required: false, loads: Objects::ProjectNext
      argument :title, String, "The title of the draft issue. This field is required.", required: false
      argument :body, String, "The body of the draft issue.", required: false
      argument :assignee_ids, [ID], "The IDs of the assignees of the draft issue.", required: false, loads: Objects::User, as: :assignees

      field :project_next_item, Objects::ProjectNextItem, "The draft issue added to the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        # Those 2 arguments are in fact _required_ but we need to mark them as _optional_ since we are deprecating this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:project, self) if inputs[:project].nil?
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:title, self) if inputs[:title].nil?

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_next_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, title:, body: nil, assignees: [])
        created_item = nil
        begin
          created_item = project.build_item(creator: context[:viewer], draft_issue_title: title)
          created_item.content = created_item.build_draft_issue(title: title, body: body, assignees: assignees)
          project.save_with_priority!(created_item, **{ position: :bottom })
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This project must be rebalanced.")
        rescue ActiveRecord::RecordInvalid => invalid
          raise Errors::Unprocessable.new(invalid.record.errors.full_messages.join(", "))
        end

        if created_item.persisted?
          { project_next_item: created_item, errors: [] }
        else
          raise Errors::Unprocessable.new(created_item.errors.full_messages.join(", "))
        end
      end
    end
  end
end
