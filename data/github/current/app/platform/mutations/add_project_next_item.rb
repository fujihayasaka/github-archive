# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectNextItem < Platform::Mutations::Base
      description "Adds an existing item (Issue or PullRequest) to a Project."
      minimum_accepted_scopes ["write:org", "repo"]

      required_capabilities [:mobile_only_schema_mask]

      argument :project_id, ID, "The ID of the Project to add the item to. This field is required.", required: false, loads: Objects::ProjectNext
      argument :content_id, ID, "The content id of the item (Issue or PullRequest). This field is required.", required: false, loads: Unions::ProjectNextItemContent

      field :project_next_item, Objects::ProjectNextItem, "The item added to the project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        # Those 2 arguments are in fact _required_ but we need to mark them as _optional_ since we are deprecating this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:project, self) if inputs[:project].nil?
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:content, self) if inputs[:content].nil?

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

      def resolve(project:, content:)
        if content.is_a?(::PullRequest) || content.is_a?(::Issue)
          content_owner = content.try(:repository).try(:owner)

          if project.owner != content_owner
            raise Errors::Validation.new("This project item doesn't belong to correct owner")
          end

          existing_item = project.memex_project_items.find_by(content_id: content.id)
          if existing_item
            existing_item.unarchive! if existing_item.archived?

            { project_next_item: existing_item, errors: [] }
          else
            created_item = project.build_item(creator: context[:viewer], issue_or_pull: content)

            begin
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
        else
          raise Errors::Validation.new("contentID must refer to an issue or pull request.")
        end
      end
    end
  end
end
