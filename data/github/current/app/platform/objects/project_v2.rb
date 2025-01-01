# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2 < Objects::Base
      include ::GitHub::UTF8

      implements Interfaces::Closable, Interfaces::Updatable

      model_name "MemexProject"

      description "New projects that manage issues, pull requests and drafts using tables and boards."

      visibility :public, environments: [:dotcom, :enterprise]

      PREFIX = Helpers::ProjectV2::Prefix.new("PVT", :opvt, :upvt)
      implements_node templates: [
          [PREFIX.org, :owner_id, :id],
          [PREFIX.user, :owner_id, :id]
        ],
        as: PREFIX.to_s,
        ready_date: "1970-01-01" do |project|
          project.async_owner.then do |owner|
            {
              prefix: owner.organization? ? PREFIX.org : PREFIX.user,
              owner_id: owner.id,
              id: project.id
            }
          end
        end

      LAYOUT_ALLOW_LIST = [:table_layout, :board_layout, :roadmap_layout].freeze

      def self.authorized?(object, context)
        unless GitHub.projects_new_enabled?
          context.add_error(GraphQL::ExecutionError.new("This feature is not enabled for GitHub Enterprise yet"))
        end
        super(object, context)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_read,
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

      minimum_accepted_scopes ["read:project"]

      DeprecationNotice = {
        start_date: Date.new(2024, 10, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "dewski",
      }

      database_id_field(deprecated: DeprecationNotice)

      full_database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this project"

      field :number, Integer, "The project's number.", null: false
      field :closed, Boolean, "Returns true if the project is closed.", null: false
      def closed
        @object.closed_at.present?
      end

      field :public, Boolean, "Returns true if the project is public.", null: false

      field :title, String, "The project's name.", null: false

      def title
        return @object.title unless @object.title.nil?

        @object.async_creator.then do |creator|
          MemexProject.default_user_title(creator)
        end
      end

      field :short_description, String, "The project's short description.", null: true

      field :readme, String, "The project's readme.", null: true
      def readme
        utf8(@object.description)
      end

      field :creator, Interfaces::Actor, "The actor who originally created the project.", null: true, method: :async_creator

      field :owner, Interfaces::ProjectV2Owner, "The project's owner. Currently limited to organizations and users.", null: false, method: :async_owner

      field :repositories, Connections.define(Objects::Repository), "The repositories the project is linked to.", connection: true, null: false,  numeric_pagination_enabled: true do
        argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end
      def repositories(order_by:)
        @object.async_memex_project_links.then do |links|
          ids = links.filter { |l| l.source_type == "Repository" }.map(&:source_id)
          Platform::Loaders::ProjectLinkedRepository.load_all(
            @object.owner_id,
            @context[:viewer],
            @context[:permission],
            ids
          ).then { |repos| Helpers::ProjectV2.order_objects(repos, order_by) }
        end
      end

      field :teams,
        Connections.define(Objects::Team),
        "The teams the project is linked to.",
        connection: true,
        null: false,
        minimum_accepted_scopes: ["read:org"],
        numeric_pagination_enabled: true do
          argument :order_by,
            Inputs::TeamOrder,
            "Ordering options for teams returned from this connection.",
            required: false,
            default_value: { field: "name", direction: "ASC" }
        end
      def teams(order_by:)
        ::Platform::Loaders::MemexProjectUserRoleByActorAndProject.load(
          project_id: @object.id,
          actor_type: ::Platform::Loaders::MemexProjectUserRoleByActorAndProject::ActorType::Team
        ).then do |user_roles|
          actor_ids = user_roles.map(&:actor_id)
          Loaders::ActiveRecord.load_all(::Team, actor_ids).then do |teams|
            Helpers::ProjectV2.order_objects(teams, order_by)
          end
        end
      end

      field :fields, Connections.define(Unions::ProjectV2FieldConfiguration), "List of fields and their constraints in the project", connection: true, null: false, numeric_pagination_enabled: true do
        argument :order_by, Inputs::ProjectV2FieldOrder, "Ordering options for project v2 fields returned from the connection", required: false,
          default_value: { field: "position", direction: "ASC" }
      end
      def fields(order_by:)
        Loaders::MemexProjectColumn.load_all(
          @object,
          @object.owner,
          @context[:viewer],
        ).then { |fields| Helpers::ProjectV2.order_objects(fields, order_by) }
      end

      field :field, Unions::ProjectV2FieldConfiguration, "A field of the project", null: true do
        argument :name, String, "The name of the field", required: true
      end
      def field(name:)
        loader = Loaders::MemexProjectColumnByName
        loader.load(
          @object,
          @object.owner,
          name,
          @context[:viewer],
        ).then do |fields|
          field = fields.is_a?(Array) ? fields.first : fields
          next field unless field.nil?

          raise Errors::NotFound, "Could not resolve to a Unions::ProjectV2FieldConfiguration with the name #{name}"
        end
      end

      field :items,
        Connections::ProjectV2Item,
        "List of items in the project",
        connection: false,
        null: false,
        numeric_pagination_enabled: true do
          has_connection_arguments
          argument :order_by,
            Inputs::ProjectV2ItemOrder,
            "Ordering options for project v2 items returned from the connection",
            required: false,
            default_value: { field: "position", direction: "ASC" }
        end
      def items(**arguments)
        async_use_elasticsearch?(Helpers::Projects::Backend::ConsumerFeatureFlag::Public, feature_flag_actor: @object).then do |elasticsearch_enabled|
          if elasticsearch_enabled
            ConnectionWrappers::ProjectV2ItemsElasticsearchQuery.new(
              memex_project: @object,
              arguments:,
              context:,
              first: arguments[:first],
              last: arguments[:last],
              after: arguments[:after],
              before: arguments[:before],
            )
          else
            ConnectionWrappers::ProjectV2ItemQuery.new(
              @object,
              arguments:,
              context:,
              first: arguments[:first],
              last: arguments[:last],
              after: arguments[:after],
              before: arguments[:before],
            )
          end
        end
      end

      field :has_reached_items_limit, Boolean, "Whether new items can be added to the project", null: false, visibility: :internal, method: :async_batch_has_exceeded_items_limit?

      field :view, Objects::ProjectV2View, "A view of the project", null: true do
        argument :number, Integer, "The number of a view belonging to the project", required: true
      end
      def view(number:)
        @object.async_batch_memex_project_views_with_filtered_layouts(LAYOUT_ALLOW_LIST).then do |views|
          unless (view = views.find { |v| v.number == number })
            raise Platform::Errors::NotFound, "Could not resolve to an Objects::ProjectV2View with the number #{number}"
          end
          view
        end
      end

      field :views, Connections.define(Objects::ProjectV2View), "List of views in the project", connection: true, null: false, numeric_pagination_enabled: true do
        argument :order_by, Inputs::ProjectV2ViewOrder, "Ordering options for project v2 views returned from the connection", required: false, default_value: { field: "position", direction: "ASC" }
      end
      def views(order_by:)
        @object
          .async_batch_memex_project_views_with_filtered_layouts(LAYOUT_ALLOW_LIST)
          .then { |views| Helpers::ProjectV2.order_objects(views, order_by, omit_ordering: true) }
      end

      field :default_view, Objects::ProjectV2View, "The default view for the project", null: true, mobile_only: true

      field :workflows, Connections.define(Objects::ProjectV2Workflow), "List of the workflows in the project", connection: true, null: false, numeric_pagination_enabled: true do
        argument :order_by, Inputs::ProjectV2WorkflowOrder, "Ordering options for project v2 workflows returned from the connection", required: false, default_value: { field: "name", direction: "ASC" }
      end
      def workflows(order_by:)
        raise Errors::Forbidden, "You do not have permission to access workflows" unless @object.viewer_can_write?(@context[:viewer])

        @object.async_workflows.then do |workflows|
          Helpers::ProjectV2.order_objects(workflows, order_by)
        end
      end

      field :workflow, Objects::ProjectV2Workflow, "A workflow of the project", null: true do
        argument :number, Integer, "The number of a workflow belonging to the project", required: true
      end
      def workflow(number:)
        raise Errors::Forbidden, "You do not have permission to access workflows" unless @object.viewer_can_write?(@context[:viewer])

        @object.workflows.find_by(number: number).then do |workflow|
          next workflow unless workflow.nil?

          raise Platform::Errors::NotFound, "Could not resolve to an Objects::ProjectV2Workflow with the number #{number}"
        end
      end

      field :status_updates, Connections.define(Objects::ProjectV2StatusUpdate),
        description: "List of the status updates in the project.",
        connection: true,
        null: false,
        numeric_pagination_enabled: true do
          argument :order_by, Inputs::ProjectV2StatusOrder, "Order for connection", required: false, default_value: { field: "created_at", direction: "DESC" }
        end
      def status_updates(order_by:)
        Helpers::ProjectV2.order_objects(@object.memex_project_statuses.filter_spam_for(context[:viewer]), order_by)
      end

      field :template, Boolean, "Returns true if this project is a template.", method: :async_batch_is_template?, null: false

      # Memex Without Limits introduced a new Search API which provides grouping, sorting, filtering, and
      # paging. Use this field to help determine which backend will be used to materialize the results for the
      # ProjectV2View#groups and ProjectV2View#group fields.
      # This can help out for things like showing an in-beta banner for users.
      field :use_elasticsearch,
        Boolean,
        description: "True if Elasticsearch will be used, false if MySQL will be used.",
        null: false,
        mobile_only: true

      def use_elasticsearch
        async_use_elasticsearch?(Helpers::Projects::Backend::ConsumerFeatureFlag::Mobile, feature_flag_actor: context[:viewer])
      end

      def async_use_elasticsearch?(consumer_feature_flag, feature_flag_actor:)
        Helpers::Projects::Backend.async_use_elasticsearch?(
          memex_project_or_view: object,
          feature_flag_actor:,
          consumer_feature_flag:
        )
      end

      field :updates_channel,
        String, "Channel value for subscribing to live updates.",
        null: true,
        mobile_only: true,
        required_capabilities: [:subscribe_alive_events],
        method: :live_updates_channel

      field :suggested_issue_type_names, [String], null: true, description: "A list of suggested organizational issue type names that the project has access to.", visibility: :internal do
        argument :limit, Integer, required: false, default_value: 10, description: "Optionally limit how many suggested issue types to return, defaults to 10, maximum of 100."
      end

      def suggested_issue_type_names(**arguments)
        limit = arguments[:limit].clamp(1, 100)

        @object.async_owner.then do |owner|
          if owner.issue_types_enabled?
            owner.async_issue_types.then do |issue_types|
              if @object.public?
                issue_types = issue_types.select { |issue_type| !issue_type.private? }
              end
              issue_types.select(&:enabled?).map(&:name).take(limit)
            end
          end
        end
      end
    end
  end
end
