# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectV2ItemById < Platform::Mutations::Base
      description "Links an existing content instance to a Project."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to add the item to.", required: true, loads: Objects::ProjectV2
      argument :content_id, ID, "The id of the Issue or Pull Request to add.", required: true, loads: Unions::ProjectV2ItemContent

      field :item, Objects::ProjectV2Item, "The item added to the project.", null: true
      field :project_edge, Objects::ProjectV2Item.edge_type, "The edge for the item added to the project.", null: true, visibility: :internal

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

      def resolve(project:, content:)
        unless content.is_a?(::PullRequest) || content.is_a?(::Issue)
          raise Errors::Validation.new("contentID must refer to an Issue or a Pull Request.")
        end

        # This describes the total number of attempts we will make to add the item to the project. Specifically, if
        # we encounter a race condition that causes us to violate the unique index on content in the
        # `memex_project_items` table, then we will retry the operation once.
        total_attempts = 2

        begin
          existing_item = project.memex_project_items.find_by(content_type: content.class.name, content_id: content.id)

          if existing_item
            existing_item.unarchive! if existing_item.archived?
            return { item: existing_item, errors: [] }
          end

          created_item = project.build_item(creator: context[:viewer], issue_or_pull: content)

          project.save_with_priority!(created_item, **{ position: :bottom })
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This project must be rebalanced.")
        rescue ActiveRecord::RecordInvalid => invalid
          raise Errors::Unprocessable.new(invalid.record.errors.full_messages.join(", "))
        rescue ActiveRecord::RecordNotUnique => duplicate
          total_attempts -= 1
          retry if total_attempts > 0
          raise Errors::Unprocessable.new("Content already exists in this project")
        end

        unless created_item.persisted?
          raise Errors::Unprocessable.new(created_item.errors.full_messages.join(", "))
        end

        target = content.kind_of?(::PullRequest) ? content.issue : content
        unless target.present?
          raise Errors::Validation.new("The pull request could not be resolved")
        end

        projects = ArrayWrapper.new(target.visible_memex_items_for(context[:viewer], include_archived: true))
        projects_connection = Platform::ConnectionWrappers::ArrayWrapper.new(projects, context: context)

        { item: created_item, project_edge: GraphQL::Pagination::Connection::Edge.new(created_item, projects_connection), errors: [] }
      end
    end
  end
end
