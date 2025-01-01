# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectV2DraftIssue < Platform::Mutations::Base
      description "Creates a new draft issue and add it to a Project."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to add the draft issue to.", required: true, loads: Objects::ProjectV2
      argument :title, String, "The title of the draft issue. A project item can also be created by providing the URL of an Issue or Pull Request if you have access.", required: true
      argument :body, String, "The body of the draft issue.", required: false
      argument :assignee_ids, [ID], "The IDs of the assignees of the draft issue.", required: false, loads: Objects::User, as: :assignees

      field :project_item, Objects::ProjectV2Item, "The draft issue added to the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_write,
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
          created_item = project.build_draft_issue(creator: context[:viewer], title: title, body: body, assignees: assignees)
          project.save_with_priority!(created_item, **{ position: :bottom })
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This project must be rebalanced.")
        rescue ActiveRecord::RecordInvalid => invalid
          raise Errors::Unprocessable.new(invalid.record.errors.full_messages.join(", "))
        end

        unless created_item.persisted?
          raise Errors::Unprocessable.new(created_item.errors.full_messages.join(", "))
        end

        { project_item: created_item, errors: [] }
      end
    end
  end
end
