# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Project < Objects::Base

      description "Projects manage issues, pull requests and notes within a project owner."

      implements_node templates: [[:op, :org_id, :project_id], [:up, :user_id, :project_id], [:rp, :repo_id, :project_id], [:mp, :mannequin_id, :project_id]], as: "PRO", ready_date: "2021-07-09", deprecated: Helpers::ProjectDeprecation::Notice do |project|
        case project.owner_type
        when "Organization"
          {
            prefix: :op,
            org_id: project.owner_id,
            project_id: project.id
          }
        when "User"
          {
            prefix: :up,
            user_id: project.owner_id,
            project_id: project.id
          }
        when "Mannequin"
          {
            prefix: :mp,
            mannequin_id: project.owner_id,
            project_id: project.id
          }
        when "Repository"
          {
            prefix: :rp,
            repo_id: project.owner_id,
            project_id: project.id
          }
        else
          raise Platform::Errors::Internal, "Unexpected project owner: #{project.owner_type.inspect}"
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, project)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        project.async_owner.then do |project_owner|
          case project.owner_type
          when "Repository"
            permission.async_owner_if_org(project_owner).then do |org|
              project_owner.async_repository_projects_enabled?.then do |enabled|
                next false unless enabled

                permission.access_allowed?(:show_project,
                  resource: project,
                  current_repo: project_owner,
                  current_org: org,
                  allow_integrations: true,
                  allow_user_via_granular_actor: true,
                )
              end
            end
          when "Organization"
            project_owner.async_organization_projects_enabled?.then do |enabled|
              next false unless enabled

              permission.access_allowed?(:show_project,
                resource: project,
                organization: project_owner,
                current_repo: nil,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
              )
            end
          when "User"
            permission.access_allowed?(:show_project,
              resource: project,
              current_repo: nil,
              current_org: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false,
            )
          else
            raise Platform::Errors::NotImplemented, "Only repository, org, and user projects are supported"
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if object.is_a?(::ProjectColumn)
          # Mutations::AddProjectCard is misconfigured, so it routes project_columns here.
          # we can't fix it yet, so accomodate it here:
          return permission.typed_can_see?("ProjectColumn", object)
        end

        if permission.viewer&.can_have_granular_permissions? && object.owner_type == "Organization"
          object.async_owner.then do |owner|
            owner.resources.organization_projects.async_readable_by?(permission.viewer)
          end
        else
          object.async_readable_by?(permission.viewer)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      implements Interfaces::Closable,
        Interfaces::Updatable

      database_id_field deprecated: Helpers::ProjectDeprecation::Notice

      created_at_field deprecated: Helpers::ProjectDeprecation::Notice

      updated_at_field deprecated: Helpers::ProjectDeprecation::Notice

      url_fields description: "The HTTP URL for this project", deprecated: Helpers::ProjectDeprecation::Notice, &:async_url

      url_fields prefix: :fullscreen, visibility: :internal, description: "The HTTP URL for viewing this project in fullscreen mode", deprecated: Helpers::ProjectDeprecation::Notice do |project|
        project.async_url.then do |url|
          url.query_values ||= {}
          url.query_values = url.query_values.merge(fullscreen: true)
          url
        end
      end

      url_fields prefix: :automation_options, visibility: :internal, description: "The HTTP URL for a column's automation options", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :new_workflow, visibility: :internal, url_suffix: "/project_workflows", description: "The HTTP URL to create new project workflows", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :edit, visibility: :internal, description: "The HTTP edit URL for this project", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :update_state, url_suffix: "/state", visibility: :internal, description: "The HTTP URL for updating this project's state", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :search_results, visibility: :internal, description: "The HTTP URL for search results for cards to add to this project", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :archived_cards, url_suffix: "/cards/archived", visibility: :internal, description: "The HTTP URL for this project's archived cards", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :add_cards_link, visibility: :internal, description: "The HTTP URL for the link to add cards to this project", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :cards, visibility: :internal, description: "The HTTP URL for this project's cards", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :columns, visibility: :internal, description: "The HTTP URL for this project's columns", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :reorder_columns, visibility: :internal, description: "The HTTP URL for reordering this project's columns", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :preview_note, visibility: :internal, description: "The HTTP URL for previewing a note", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :activity, visibility: :internal, description: "The HTTP URL for this project's activity", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :clone, url_suffix: "/clone", visibility: :internal, description: "The HTTP URL for cloning this project", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :migrate, url_suffix: "/migrate", visibility: :internal, description: "The HTTP URL for migrating this project", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :dismiss_notice, url_suffix: "/dismiss_notice", visibility: :internal, description: "The HTTP URL for dismissing project notices", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :target_owner_results, url_suffix: "/target_owner_results", visibility: :internal, description: "The HTTP URL for valid project owners when cloning", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :linkable_repositories, url_suffix: "/linkable_repositories", visibility: :internal, description: "The HTTP URL for searching repositories for linking", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :settings, visibility: :internal, description: "The HTTP URL for this project's settings", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :org_settings, url_suffix: "/settings/org", visibility: :internal, description: "The HTTP URL for this project's organization settings", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :teams_settings, url_suffix: "/settings/teams", visibility: :internal, description: "The HTTP URL for this project's team settings", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :teams_settings_team_results, url_suffix: "/settings/teams/team_results", visibility: :internal, description: "The HTTP URL for this project's team results when searching for a team to add", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :users_settings, url_suffix: "/settings/users", visibility: :internal, description: "The HTTP URL for this project's collaborator settings", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :admins_settings, url_suffix: "/settings/admins", visibility: :internal, description: "The HTTP URL for a list of this project's administrators", deprecated: Helpers::ProjectDeprecation::Notice
      url_fields prefix: :linked_repositories_settings, url_suffix: "/settings/linked_repositories", visibility: :internal, description: "The HTTP URL for adding and removing linked repositories", deprecated: Helpers::ProjectDeprecation::Notice

      field :organization_permission, Enums::ProjectPermission, "The permission that all members of the owning organization have on this project.", visibility: :internal, null: true, deprecated: Helpers::ProjectDeprecation::Notice
      def organization_permission
        @object.async_owner.then do |_|
          @object.org_permission&.to_s || "none"
        end
      end

      field :number, Integer, "The project's number.", null: false, deprecated: Helpers::ProjectDeprecation::Notice
      field :state, Enums::ProjectState, "Whether the project is open or closed.", null: false, deprecated: Helpers::ProjectDeprecation::Notice
      field :name, String, "The project's name.", null: false, deprecated: Helpers::ProjectDeprecation::Notice
      field :is_public, Boolean, "Whether the project is saved as public", null: false, method: :public, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice

      field :public_project_or_owner, Boolean, "Whether the project is publicly visible", null: false, visibility: :internal, method: :async_public_project_or_owner?, deprecated: Helpers::ProjectDeprecation::Notice

      field :track_progress, Boolean, "Whether project progress should be tracked or not", null: false, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      field :body, String, "The project's description body.", null: true, deprecated: Helpers::ProjectDeprecation::Notice
      field :body_html, Scalars::HTML, "The projects description body rendered to HTML.", null: false, deprecated: Helpers::ProjectDeprecation::Notice
      def body_html
        markdown = CommonMarker.render_html(@object.body || "", [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
        GitHub::Goomba::SimplePipeline.to_html(markdown)
      end

      field :creator, Interfaces::Actor, "The actor who originally created the project.", null: true, method: :async_creator, deprecated: Helpers::ProjectDeprecation::Notice

      field :owner, Interfaces::ProjectOwner, "The project's owner. Currently limited to repositories, organizations, and users.", null: false, method: :async_owner, deprecated: Helpers::ProjectDeprecation::Notice

      field :websocket, String, "The web socket channel ID for live updates.", null: false, method: :channel, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      field :metadata_websocket, String, "The web socket channel ID for project metadata live updates.", null: false, method: :metadata_channel, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice

      field :search_query_for_viewer, String, "The search query that the current viewer has saved", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def search_query_for_viewer
        @context[:viewer] ? @object.search_query_for(@context[:viewer]) : ""
      end

      field :columns, Connections.define(Objects::ProjectColumn), "List of columns in the project", null: false, numeric_pagination_enabled: true, deprecated: Helpers::ProjectDeprecation::Notice

      def columns(**arguments)
        @object.columns.scoped
      end

      # TODO - indec - when we're feeling launch-y, mark this endpoint as deprecated
      field :pending_cards, "List of pending cards in this project", connection: false, null: false, resolver: Platform::Resolvers::ProjectCardsBackwardsCompatibilityPending, deprecated: Helpers::ProjectDeprecation::Notice

      # TODO - indec - when we're feeling launch-y, remove the internal visibility and re-dump the schema
      field :cards, "List of cards in this project", visibility: :internal, numeric_pagination_enabled: true, connection: false, null: false, resolver: Resolvers::ProjectCards do
        argument :include_pending, Boolean, "Include pending cards in the returned cards", required: false, default_value: true
        argument :include_triaged, Boolean, "Include cards already in columns in the returned cards", required: false, default_value: true

        deprecated **Helpers::ProjectDeprecation::Notice
      end

      field :workflows, Connections.define(Objects::ProjectWorkflow), "List of workflows in the project", null: false, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def workflows
        @object.project_workflows.scoped
      end

      field :migration_status, Enums::ProjectMigrationStatusType, "Migration status of the project", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice

      def migration_status
        viewer = context[:viewer]

        return nil if viewer.nil?

        @object.async_project_migration.then do |project_migration|
          next "READY" if project_migration.nil?

          status_payload = project_migration.status_payload

          next status_payload[:status]
        end
      end

      field :viewer_can_administer, Boolean, "Check if the current viewer can administer this object.", null: false, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def viewer_can_administer
        @object.async_viewer_can_administer?(@context[:viewer])
      end

      # TODO why is a string required here instead of a direct constant reference? because circular ref?
      field :teams, "Platform::Connections::ProjectTeam", "A list of teams that have access to this project.", null: false, visibility: :internal, connection: true, deprecated: Helpers::ProjectDeprecation::Notice
      def teams
        return ::Team.none unless @object.owner_type == "Organization"

        @object.async_owner.then do
          @object.visible_teams_for(@context[:viewer]).order("slug ASC")
        end
      end

      field :collaborators, "Platform::Connections::ProjectUser", "A list of users that have direct access to this project.", null: false, visibility: :internal, connection: true, deprecated: Helpers::ProjectDeprecation::Notice
      def collaborators
        context[:permission].async_can_list_collaborators?(object).then do |can_list_collabs|
          if can_list_collabs
            @object.direct_collaborators.order("login ASC").filter_spam_for(@context[:viewer])
          else
            ::User.none
          end
        end
      end

      field :addable_teams_for_viewer, Connections.define(Objects::Team), "A list of teams that could be added to this project by the current viewer", null: false, visibility: :internal, connection: true, deprecated: Helpers::ProjectDeprecation::Notice do
        argument :query, String, "If non-null, filters teams with query on team name and team slug", required: false
      end
      def addable_teams_for_viewer(arguments = {})
        @object.async_owner.then do
          @object.addable_teams_for(@context[:viewer], query: arguments[:query])
        end
      end

      field :users_with_access, Connections.define(Objects::User), "A list of users who have access to this project", null: false, visibility: :internal, connection: true, numeric_pagination_enabled: true, deprecated: Helpers::ProjectDeprecation::Notice do
        argument :permission, Enums::ProjectPermission, "Minimum level of project access", required: false, default_value: "read"
        argument :affiliation, Enums::CollaboratorAffiliation, "Collaborators' affiliation level with the project.", required: false
      end
      def users_with_access(arguments = {})
        if @object.owner_type == "Repository"
          raise Platform::Errors::Unprocessable.new("Permissions are disabled for this project.")
        end

        @object.async_owner.then do
          permission = arguments[:permission].to_sym

          users_scope = case arguments[:affiliation]
          when "outside"
            @object.outside_collaborators(permission: permission)
          when "direct"
            @object.direct_collaborators(permission: permission)
          else
            @object.users_with_access(permission: permission)
          end

          users_scope.order(:id).filter_spam_for(@context[:viewer])
        end
      end

      field :user_permission, Enums::ProjectPermission, null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice do
        description "A user's permission on the project"
        argument :user_id, ID, "ID of the user whose permission we're trying to get", required: true
      end
      def user_permission(arguments = {})
        if @object.owner_type == "Repository"
          raise Platform::Errors::Unprocessable.new("Permissions are disabled for this project.")
        end

        user = Helpers::NodeIdentification.typed_object_from_id([Objects::User], arguments[:user_id], @context)

        if action = ::Authorization.service.most_capable_action_between(actor: user, subject: @object)
          action.to_s
        else
          "none"
        end
      end

      field :progress, Objects::ProjectProgress, "Project progress details.", null: false, deprecated: Helpers::ProjectDeprecation::Notice

      field :source_kind, String, "Source type when not created from scratch", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice

      field :source_id, Integer, "ID of source", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice

      field :locked_for_resync_by, String, "Message to display when project locked for automation resync.", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def locked_for_resync_by
        @object.locked_for?(::Project::ProjectLock::PROJECT_RESYNCING)
      end

      field :locked_for_cloning_by, String, "Message to display when project locked for cloning.", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def locked_for_cloning_by
        @object.locked_for?(::Project::ProjectLock::PROJECT_CLONING)
      end

      field :linked_repositories, [Objects::Repository, null: true], "A list of repositories linked to this project.", null: true, visibility: :under_development, deprecated: Helpers::ProjectDeprecation::Notice
      def linked_repositories
        @object.async_linked_repositories_viewer_can_see(context[:viewer])
      end

      field :has_max_linked_repositories, Boolean, "Whether this project has the maximum number of repositories linked.", null: false, visibility: :under_development, deprecated: Helpers::ProjectDeprecation::Notice
      def has_max_linked_repositories
        @object.async_project_repository_links.then do
          @object.project_repository_links.count >= ::Project::MAX_REPOSITORY_LINKS
        end
      end

      field :suggested_repositories_to_link, [Objects::Repository, null: true], "Suggestions for repositories that could be linked to this project.", null: true, visibility: :internal, deprecated: Helpers::ProjectDeprecation::Notice
      def suggested_repositories_to_link
        @object.async_owner.then do
          case @object.owner_type
          when "Repository"
            @object.suggested_repositories_to_link(actor: context[:viewer])
          when "Organization"
            @object.owner.async_org_repositories.then do
              @object.suggested_repositories_to_link(actor: context[:viewer])
            end
          when "User"
            @object.owner.async_repositories.then do
              @object.suggested_repositories_to_link(actor: context[:viewer])
            end
          end
        end
      end
    end
  end
end
