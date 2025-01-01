# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNext < Objects::Base
      include ::GitHub::UTF8

      model_name "MemexProject"
      required_capabilities [:mobile_only_schema_mask]

      description "New projects that manage issues, pull requests and drafts using tables and boards."

      # Currently, only organizations and users can own Memex projects.
      implements_node templates: [[:opn, :org_id, :project_next_id], [:upn, :user_id, :project_next_id]], as: "PN", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |project_next|
        project_next.async_owner.then do |owner|
          if owner.organization?
            {
              prefix: :opn,
              org_id: project_next.owner_id,
              project_next_id: project_next.id
            }
          elsif owner.user?
            {
              prefix: :upn,
              user_id: project_next.owner_id,
              project_next_id: project_next.id
            }
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        object.async_owner.then do |owner|
          current_org = owner if owner.organization?
          permission.access_allowed?(
            :project_next_read,
            current_org: current_org,
            resource: object,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.deleted_at.nil? && object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:org", "repo"]

      implements Interfaces::Closable,
        Interfaces::Updatable

      database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this project"

      field :number, Integer, "The project's number.", null: false
      field :closed, Boolean, "Returns true if the project is closed.", null: false
      def closed
        @object.closed_at.present?
      end

      field :public, Boolean, "Returns true if the project is public.", null: false

      field :title, String, "The project's name.", null: true

      def title
        return @object.title unless @object.title.nil?

        @object.async_creator.then do |creator|
          MemexProject.default_user_title(creator)
        end
      end

      field :description, String, "The project's description.", null: true
      def description
        utf8(@object.description)
      end

      field :short_description, String, "The project's short description.", null: true

      field :creator, Interfaces::Actor, "The actor who originally created the project.", null: true, method: :async_creator

      field :owner, Interfaces::ProjectNextOwner, "The project's owner. Currently limited to organizations and users.", null: false, method: :async_owner

      field :repositories, Connections.define(Objects::Repository), "The repositories the project is linked to.", connection: true, null: false,  numeric_pagination_enabled: true
      def repositories
        @object.async_memex_project_links.then do |links|
          ids = links.filter { |l| l.source_type == "Repository" }.map(&:source_id)
          Platform::Loaders::ProjectLinkedRepository.load_all(
            @object.owner_id,
            @context[:viewer],
            @context[:permission],
            ids
          ).then { |repos| ArrayWrapper.new(repos.compact) }
        end
      end

      field :fields, Connections.define(Objects::ProjectNextField), "List of fields in the project", connection: true, null: false, numeric_pagination_enabled: true
      def fields
        @object.async_memex_project_columns.then do |columns|
          ArrayWrapper.new(columns.reject(&:issue_type?))
        end
      end

      field :field_constraints, Connections.define(Unions::ProjectNextFieldConfiguration), "List of fields and their constraints in the project", connection: true, null: false, numeric_pagination_enabled: true
      def field_constraints
        @object.async_owner.then do |owner|
          Loaders::MemexProjectColumn.load_all(
            @object,
            owner,
            @context[:viewer],
            v2: false
          ).then { |fields| ArrayWrapper.new(fields) }
        end
      end

      field :items, Connections.define(Objects::ProjectNextItem), "List of items in the project", connection: true, null: false, numeric_pagination_enabled: true do
        argument :filter, String, "Query to filter project items by", required: false, required_capabilities: [:mobile_only_schema_mask]
      end
      def items(filter: "")
        if filter.blank?
          @object.memex_project_items.not_archived
        else
          @object.async_memex_project_items.then do |items|
            items = items.reject(&:archived?).reverse

            @object.async_filter_items(memex_items: items, filter: filter, viewer: @context[:viewer]).then do |filtered_items|
              ArrayWrapper.new(filtered_items)
            end
          end
        end
      end

      field :views, Connections.define(Objects::ProjectView), "List of views in the project", connection: true, null: false, numeric_pagination_enabled: true
      def views
        @object.async_memex_project_views.then do |views|
          ArrayWrapper.new(views)
        end
      end

      field :default_view, Objects::ProjectView, "The default view for the project", null: true, required_capabilities: [:mobile_only_schema_mask]
    end
  end
end
