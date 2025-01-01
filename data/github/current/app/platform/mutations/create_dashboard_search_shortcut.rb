# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateDashboardSearchShortcut < Mutations::Base
      description "Create a new dashboard search shortcut for the current viewer."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]
      extras [:execution_errors]

      input_object_class Inputs::SearchShortcutAttributes
      error_fields

      field :dashboard, Objects::UserDashboard, "The dashboard owning the shortcut", null: true
      field :shortcut, Objects::SearchShortcut, "The created search shortcut.", null: true
      field :shortcut_edge, Objects::SearchShortcut.edge_type, "The edge from the dashboard to the created search shortcut.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(execution_errors:, **inputs)
        dashboard = context[:viewer].dashboard || ::UserDashboard.create!(user: context[:viewer])

        scoping_repo =
          if inputs[:scoping_repository].present?
            Helpers::RepositoryByNwo.async_repository_with_owner(
              login: inputs.dig(:scoping_repository, :owner),
              name: inputs.dig(:scoping_repository, :name),
              permission: context[:permission],
              viewer: context[:viewer],
              follow_repo_redirect: true
            ).sync
          end

        shortcut = dashboard.shortcuts.build({
          name: inputs[:name],
          description: inputs[:description],
          query: inputs[:query].to_s,
          search_type: inputs[:search_type],
          color: inputs[:color],
          icon: inputs[:icon],
          scoping_repository_id: scoping_repo&.id
        })

        if shortcut.valid?
          begin
            shortcut_connection = Platform::ConnectionWrappers::Relation.new(dashboard.shortcuts, context: context)
            shortcut_edge = GraphQL::Pagination::Connection::Edge.new(shortcut, shortcut_connection)

            dashboard.prioritize_dependent!(shortcut, position: :bottom)
            {
              dashboard: dashboard,
              shortcut: shortcut,
              shortcut_edge: shortcut_edge,
              errors: []
            }
          rescue GitHub::Prioritizable::Context::LockedForRebalance
            raise Errors::ServiceUnavailable.new("This user dashboard is temporarily locked for maintenance. Please try again.")
          end
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(shortcut, execution_errors)

          {
            dashboard: nil,
            shortcut: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(shortcut)
          }
        end
      end
    end
  end
end
