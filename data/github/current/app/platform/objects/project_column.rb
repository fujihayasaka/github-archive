# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectColumn < Platform::Objects::Base
      description "A column inside a project."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, project_column)
        project_column.async_project.then do |project|
          permission.typed_can_access?("Project", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_project(object)
      end

      minimum_accepted_scopes ["public_repo"]

      implements_node templates: [
          [:urpc, :user_id, :repository_id, :project_id, :project_column_id],
          [:orpc, :organization_id, :repository_id, :project_id, :project_column_id],
          # ^^ these are from an early attempt which included the repo owner. We're not using them anymore
          # but they should stay here for compatibility.
          [:upc, :user_id, :project_id, :project_column_id],
          [:opc, :organization_id, :project_id, :project_column_id],
          [:rpc, :repository_id, :project_id, :project_column_id],
        ],
        as: "PC", ready_date: "2021-03-18" do |project_column|
        id_values = {
          project_id: project_column.project_id,
          project_column_id: project_column.id,
        }

        project_column.async_project.then do |project|
          case project.owner_type
          when "Repository"
            id_values.merge(prefix: :rpc, repository_id: project.owner_id)
          when "Organization"
            id_values.merge(organization_id: project.owner_id, prefix: :opc)
          when "User"
            id_values.merge(user_id: project.owner_id, prefix: :upc)
          else
            raise Platform::Errors::Internal, "Unexpected project owner_type: #{project.owner_type.inspect}"
          end
        end
      end

      database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this project column" do |project_column|
        project_column.async_url
      end

      url_fields prefix: :cards, visibility: :internal, description: "The HTTP URL for this project column's cards" do |project_column|
        project_column.async_url("/cards")
      end

      url_fields prefix: :workflow, visibility: :internal, description: "The HTTP URL for this project column's workflow" do |project_column|
        project_column.async_url("/workflow")
      end

      url_fields prefix: :archive, url_suffix: "/archive", visibility: :internal, description: "The HTTP URL for archiving the cards in a project column"

      field :name, String, "The project column's name.", null: false

      field :project, Platform::Objects::Project, "The project that contains this column.", null: false

      def project
        Loaders::ActiveRecord.load(::Project, @object.project_id)
      end

      field :purpose, Enums::ProjectColumnPurpose, "The semantic purpose of the column", null: true

      field :cards, resolver: Resolvers::ProjectCards, description: "List of cards in the column", numeric_pagination_enabled: true, null: false, connection: false

      field :workflows, Connections.define(Objects::ProjectWorkflow), visibility: :internal, description: "List of workflows associated with the project column", null: false, connection: true

      def workflows
        @object.project_workflows.scoped
      end

      field :cards_count_project_column_view, Integer, description: "count of cards that don't have issues belonging to disabled issues repos", null: false, visibility: :internal

      def cards_count_project_column_view
        @object.cards_count_project_column_view
      end
    end
  end
end
