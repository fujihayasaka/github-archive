# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Team < Platform::Objects::Base
      description "A team of users in an organization."

      ViewerMembershipError = Class.new(StandardError)

      implements_node templates: [[:t, :organization_id, :id]], as: "T", ready_date: "2021-07-09" do |team|
        {
          prefix: :t,
          organization_id: team.organization_id,
          id: team.id,
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, team)
        team.async_organization.then do |org|
          permission.access_allowed?(:v4_get_team, team: team, resource: org, organization: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if GitHub.enterprise? && permission.viewer&.site_admin?
        object.async_visible_to?(permission.viewer)
      end

      minimum_accepted_scopes ["read:org", "read:discussion"]

      implements Interfaces::Subscribable
      implements Interfaces::MemberStatusable

      field :name, String, "The name of the team.", null: false
      field :description, String, "The description of the team.", null: true
      field :privacy, Enums::TeamPrivacy, "The level of privacy the team has.", null: false
      field :notification_setting, Enums::TeamNotificationSetting, "The notification setting that the team has set.", null: false
      field :slug, String, "The slug corresponding to the team.", null: false

      field :avatar_url, Scalars::URI, description: "A URL pointing to the team's avatar.", null: true do
        argument :size, Integer, "The size in pixels of the resulting square image.", default_value: 400, required: false
      end

      def avatar_url(size:)
        if GitHub.private_mode_enabled? && !GitHub.multi_tenant_enterprise? && Apps::Privileged.capable?(:enterprise_avatar_display, app: context[:oauth_app])
          "#{GitHub.api_url}/enterprise/avatars#{@object.primary_avatar_path}?s=#{size}"
        else
          @object.primary_avatar_url(size)
        end
      end

      database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this team" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "new_team", description: "The HTTP URL creating a new team" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/new-team")
          template.expand org: org.display_login
        end
      end

      url_fields prefix: "edit_team", description: "The HTTP URL for editing this team" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/edit")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "discussions", description: "The HTTP URL for team discussions" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/discussions")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "repositories", description: "The HTTP URL for this team's repositories" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/repositories")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "projects", description: "The HTTP URL for this team's projects", visibility: :internal do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/projects")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "team_projects_suggestions", description: "The HTTP URL for suggesting org projects to add to this team", visibility: :internal do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/projects/suggestions")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "teams", description: "The HTTP URL for this team's teams" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/teams")
          template.expand org: org.display_login, team: team.slug
        end
      end

      url_fields prefix: "members", description: "The HTTP URL for the team' members" do |team|
        team.async_organization.then do |org|
          template = Addressable::Template.new("/orgs/{org}/teams/{team}/members")
          template.expand org: org.display_login, team: team.slug
        end
      end

      field :combined_slug, String, description: "The slug corresponding to the organization and team.", null: false

      def combined_slug
        @object.async_organization.then do |org|
          "#{org.display_login}/#{@object.slug}"
        end
      end

      field :parent_team, Team, description: "The parent team of the team.", method: :async_batch_parent_team, null: true

      field :viewer_can_administer, Boolean, description: "Team is adminable by the viewer.", null: false

      def viewer_can_administer
        @object.async_adminable_by?(@context[:viewer])
      end

      field :is_legacy_admin_team, Boolean, visibility: :internal, method: :legacy_admin?, description: "Teams that were created with the admin permission level under the legacy organization permissions structure.", null: false

      field :is_legacy_owners_team, Boolean, visibility: :internal, method: :legacy_owners?, description: "Whether this team is a legacy owners teams.", null: false

      field :viewer_membership, Enums::TeamMembershipState, visibility: :internal, description: "Identifies if the viewer can leave, join, or cancel membership to this team", null: false

      def viewer_membership
        @object.async_ldap_mapping.then do
          @object.available_membership_action_for(@context[:viewer]).to_s
        end
      end

      field :is_viewer_member, Boolean, visibility: :internal, description: "Identifies if the viewer is a member of this team.", null: false
      def is_viewer_member
        @object.async_member?(context[:viewer])
      end

      field :externally_managed, Boolean, visibility: :internal, method: :async_externally_managed?, description: "The team has one or more external mappings.", null: false

      field :locally_managed, Boolean, visibility: :internal, method: :async_locally_managed?, description: "The team does not have one or more external mappings", null: false

      field :has_ldap_mapping, Boolean, visibility: :internal, description: "The team has an LDAP mapping.", null: true

      def has_ldap_mapping
        @object.async_ldap_mapping.then do |_ldap_mapping|
          @object.ldap_mapped?
        end
      end

      field :ldap_mapping_is_gone, Boolean, visibility: :internal, description: "Whether the team's LDAP mapping status is 'gone'.", null: false

      def ldap_mapping_is_gone
        @object.async_ldap_mapping.then do |_ldap_mapping|
          !!@object.ldap_mapping.try(:gone?)
        end
      end

      field :ldap_dn, String, visibility: :internal, description: "The team's LDAP DN.", null: true

      def ldap_dn
        @object.async_ldap_mapping.then do |_ldap_mapping|
          @object.ldap_dn
        end
      end

      field :ldap_synced, Boolean, visibility: :internal, description: "The team's LDAP sync status.", null: false

      def ldap_synced
        @object.async_ldap_mapping.then do |_ldap_mapping|
          @object.ldap_synced?
        end
      end

      field :has_child_teams, Boolean, visibility: :internal, method: :has_child_teams?, description: "Whether this team has any child teams.", null: false

      field :members, Connections::TeamMember, numeric_pagination_enabled: true, description: "A list of users who are members of this team.", null: false, connection: false do
        has_connection_arguments
        argument :query, String, "The search string to look for.", required: false
        argument :membership, Enums::TeamMembershipType, "Filter by membership type", default_value: "all", required: false
        argument :role, Enums::TeamMemberRole, "Filter by team member role", required: false
        argument :order_by, Inputs::TeamMemberOrder, "Order for the connection.", required: false
        argument :max_members_limit, Integer, visibility: :internal, description: "The maximum number of team members to retrieve", required: false, default_value: 75000
      end

      def members(**arguments)
        arguments[:max_members_limit] ||= 75000
        if arguments[:first].nil? && arguments[:last].nil?
          arguments[:first] = Schema::DEFAULT_MAX_PER_PAGE
        end
        # We don't pass in any initial scope as the subclass of Relation used here does that itself.
        Platform::ConnectionWrappers::TeamMembers.new(
          nil,
          first: arguments[:first],
          last: arguments[:last],
          before: arguments[:before],
          after: arguments[:after],
          arguments: arguments,
          parent: @object,
          context: @context
        )
      end

      field :repositories, Connections::TeamRepository, null: false, numeric_pagination_enabled: true, connection: false do
        description "A list of repositories this team has access to."

        has_connection_arguments

        argument :query, String, "The search string to look for. Repositories will be returned where the name contains your search string.", required: false
        argument :order_by, Inputs::TeamRepositoryOrder, "Order for the connection.", required: false
        argument :affiliation, Enums::TeamRepositoryType, "Filter by affiliation", default_value: "all", visibility: :internal, required: false
      end

      def repositories(**arguments)
        arguments[:affiliation] ||= "all"
        @object.async_organization.then do |organization|
          organization.async_business.then do
            Platform::ConnectionWrappers::TeamRepositories.new(
              @object,
              **T.unsafe({ **arguments,
              affiliation: arguments[:affiliation].downcase.to_sym,
              context: @context,
              field: @field })
            )
          end
        end
      end

      field :projects, Connections::TeamProject, visibility: :internal, null: false, numeric_pagination_enabled: true, deprecated: Helpers::ProjectDeprecation::Notice do
        description "A list of projects this team has access to."
        # We may want to keep the id argument private even when this connection
        # is made public, as we only added it to power a REST API endpoint.
        argument :id, ID, "Only get the project with this ID", visibility: :internal, required: false
        argument :affiliation, Enums::TeamProjectType, "Filter by affiliation", default_value: "all", visibility: :internal, required: false
      end

      def projects(**arguments)
        arguments[:affiliation] ||= "all"
        promises = [@object.async_organization]

        if @context[:viewer].is_a?(::Bot)
          promises << Loaders::ActiveRecordAssociation.load(@context[:viewer].installation, :target)
        end

        Promise.all(promises).then do
          if @context[:permission].can_list_projects?(@object.organization)
            affiliation = arguments[:affiliation].downcase.to_sym
            scope = @object.visible_projects_for(@context[:viewer], affiliation: affiliation)

            if arguments[:id]
              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::Project], arguments[:id], @context).then do |project|
                if project
                  scope.where(id: project.id)
                else
                  ::Project.none
                end
              end
            else
              scope
            end
          else
            ::Project.none
          end
        end
      end

      field :addable_projects_for_viewer, resolver: Resolvers::ProjectsAddableToTeam, visibility: :internal, description: "A list of projects that the viewer could add to this team", connection: true, deprecated: Helpers::ProjectDeprecation::Notice

      field :invitations, Connections.define(Objects::OrganizationInvitation), description: "A list of pending invitations for users to this team", null: true, connection: true

      def invitations
        @object.async_adminable_by?(@context[:viewer]).then do |is_adminable_by_viewer|
          if is_adminable_by_viewer || (Platform.requires_scope?(@context[:origin]) && @context[:permission].can_list_team_invitations?(@object))
            @object.pending_invitations.filter_spam_for(@context[:viewer])
          else
            @object.pending_invitations.none
          end
        end
      end

      field :membership_requests, Connections.define(Objects::TeamMembershipRequest), visibility: :internal, description: "A list of pending membership requests for this team.", null: false, connection: true

      def membership_requests
        if @object.adminable_by?(@context[:viewer])
          @object.pending_team_membership_requests.filter_spam_for(@context[:viewer])
        else
          ::TeamMembershipRequest.none
        end
      end

      field :pending_team_change_parent_requests, Connections.define(Objects::TeamChangeParentRequest), visibility: :internal, description: "A list of pending requests to move teams to another parent team.", null: false, connection: true do
        argument :direction, Enums::TeamChangeParentRequestDirection, "The direction for the change requests to return", default_value: "all", required: false

      end

      def pending_team_change_parent_requests(**arguments)
        @object.pending_change_parent_requests(direction: arguments[:direction])
      end

      field :ancestors, resolver: Platform::Resolvers::Ancestors, description: "A list of teams that are ancestors of this team.", connection: true

      field :child_teams, resolver: Resolvers::ChildTeams, numeric_pagination_enabled: true, description: "List of child teams belonging to this team", connection: true

      field :discussions, Connections.define(Objects::TeamDiscussion), numeric_pagination_enabled: true, description: "A list of team discussions.", null: false do
        argument :is_pinned, Boolean, "If provided, filters discussions according to whether or not they are pinned.", required: false
        argument :order_by, Inputs::TeamDiscussionOrder, "Order for connection", required: false
      end

      field :dashboard, Objects::TeamDashboard, description: "Dashboard for this team.", null: true, required_capabilities: [:mobile_only_schema_mask]

      def dashboard
        object.async_dashboard.then do |dashboard|
          dashboard.presence || ::TeamDashboard.new(team: object)
        end
      end

      def discussions(**arguments)
        scope = @object.discussion_posts

        @object.async_organization.then do |org|
          org.async_team_discussions_allowed?.then do |discussions_allowed|
            next scope.none unless discussions_allowed

            org.async_adminable_by?(@context[:viewer]).then do |adminable|
              Platform::Loaders::IsTeamMemberCheck
                .load(@context[:viewer].id, @object.id)
                .then do |team_member|

                unless team_member || adminable
                  scope = scope.where(private: false)
                end

                unless arguments[:is_pinned].nil?
                  condition = arguments[:is_pinned] ? "NOT NULL" : "NULL"
                  scope = scope.where("discussion_posts.pinned_at IS #{condition}")
                end

                if (ordering = arguments[:order_by])
                  scope = scope.order(
                    "discussion_posts.#{ordering[:field]} #{ordering[:direction]}")
                end

                scope.scoped
              end
            end
          end
        end
      end

      field :discussion, Objects::TeamDiscussion, description: "Find a team discussion by its number.", null: true do
        argument :number, Integer, "The sequence number of the discussion to find.", required: true
      end

      def discussion(**arguments)
        Platform::Loaders::TeamDiscussionByNumber.load(@object.id, arguments[:number]).then do |post|
          post && post.async_readable_by?(@context[:viewer]).then { |visible| post if visible }
        end
      end

      field :viewer_can_create_team_post, Boolean, visibility: :internal, description: "Team post is allowed to created by the viewer.", null: false

      def viewer_can_create_team_post
        @object.async_fgp_team_post_creatable?(@context[:viewer])
      end

      field :organization, Objects::Organization, description: "The organization that owns this team.", null: false, method: :async_organization

      field :permission, Enums::LegacyTeamPermission, visibility: :internal, description: "The legacy team permission.", null: true do
        deprecated(
          start_date: Date.new(2018, 2, 1),
          reason: "The permission attr is a legacy value.",
          superseded_by: "Use team member roles and team repo permissions instead.",
          owner: "xuorig",
        )
      end

      def permission
        @object.permission.blank? ? "pull" : @object.permission
      end

      field :projects_v2,
        Connections.define(Objects::ProjectV2),
        minimum_accepted_scopes: ["read:project"],
        description: "List of projects this team has collaborator access to.",
        numeric_pagination_enabled: true,
        null: false do
          argument :order_by,
            Inputs::ProjectV2Order,
            "How to order the returned projects.",
            required: false,
            default_value: { field: "number", direction: "DESC" }
          argument :filter_by,
            Inputs::ProjectV2Filters,
            "Filtering options for projects returned from this connection",
            required: false,
            default_value: {}
          argument :query,
            String,
            "The query to search projects by.",
            required: false,
            default_value: ""
          argument :use_full_term_query,
            Boolean,
            "Search project titles that match the entire query string",
            required: false,
            default_value: false,
            visibility: :internal
          argument :min_permission_level,
            Enums::ProjectV2PermissionLevel,
            "Filter projects based on user role.",
            required: false,
            default_value: "read"
        end

      def projects_v2(query:, filter_by:, order_by:, min_permission_level:, use_full_term_query: false)
        validate_projects_v2_arguments(query, filter_by)
        if filter_by.present?
          query = "#{query.strip} is:#{filter_by[:state]}" if filter_by[:state].present?
        end

        Loaders::ProjectV2ByQuery.load(
          @object,
          @context[:viewer],
          query,
          min_permission_level,
          use_full_term_query
        ).then do |memexes|
          Helpers::ProjectV2.order_objects(memexes, order_by)
        end
      end

      def validate_projects_v2_arguments(query, filter_by)
        return unless query.present? || filter_by.present?

        if query.present? && query.include?("is:") && filter_by[:state].present?
          raise Errors::ArgumentError.new("Cannot specify both a query containing `is:` and a filterBy state.")
        end
      end

      field :project_v2,
        Objects::ProjectV2,
        minimum_accepted_scopes: ["read:project"],
        description: "Finds and returns the project according to the provided project number.",
        null: true do
          argument :number, Integer, "The Project number.", required: true
        end
      def project_v2(number:)
        Loaders::ProjectV2ByNumber.load(@object.organization, @context[:viewer], number).then do |project|
          Helpers::ProjectV2.async_validate_project_by_number(project, number, @context[:permission]).then do |project|
            ::Platform::Loaders::MemexProjectUserRoleByActorAndProject.load(
              project_id: project.id,
              actor_id: @object.id,
              actor_type: ::Platform::Loaders::MemexProjectUserRoleByActorAndProject::ActorType::Team
            ).then do |user_roles|
              if user_roles.present?
                project
              else
                raise Errors::NotFound, "Could not resolve to a ProjectV2 with the number #{number}."
              end
            end
          end
        end
      end

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for team discussion live updates.", null: false

      def websocket
        GitHub::WebSocket::Channels.team(@object)
      end

      field :group_mappings, Connections.define(Objects::TeamGroupMapping), null: true do
        visibility :internal
        description "Groups mapped to team for Team Sync"
        argument :order_by, Inputs::TeamGroupMappingOrder, "Order for the connection.", required: false,
          default_value: { field: "id", direction: "ASC" }
      end

      def group_mappings(**arguments)
        scope = @object.group_mappings
        if (ordering = arguments[:order_by])
          scope = scope.order(
            "team_group_mappings.#{ordering[:field]} #{ordering[:direction]}",
          )
        end
        scope
      end

      field :is_team_post_creation_disabled, Boolean, visibility: :internal, description: "Is team post creation disabled?", null: false, method: :team_post_creation_disabled?

      field :can_be_externally_managed, Boolean, visibility: :internal, method: :async_can_be_externally_managed?, description: "True if this team can be managed by identity provider groups via team sync.", null: false

      field :review_request_delegation_enabled, Boolean, description: "True if review assignment is enabled for this team", null: false, method: :review_request_delegation_enabled

      field :review_request_delegation_algorithm, Enums::TeamReviewAssignmentAlgorithm, description: "What algorithm is used for review assignment for this team", null: true, method: :review_request_delegation_algorithm

      field :review_request_delegation_member_count, Int, description: "How many team members are required for review assignment for this team", null: true, method: :review_request_delegation_member_count

      field :review_request_delegation_notify_team, Boolean, description: "When assigning team members via delegation, whether the entire team should be notified as well.", null: false, method: :review_request_delegation_notify_team

      field :review_request_delegation_remove_team_request, Boolean, description: "When assigning team members via delegation, whether the review request to the team should be removed.", null: false, method: :review_request_delegation_remove_team_request, visibility: :under_development

      field :review_request_delegation_include_child_team_members, Boolean, description: "When assigning team members via delegation, whether any child team members should be included in assignment.", null: false, method: :review_request_delegation_include_child_team_members, visibility: :under_development

      field :review_request_delegation_count_members_already_requested, Boolean, description: "When assigning team members via delegation, count existing member requests against the number of required members.", null: false, method: :review_request_delegation_count_members_already_requested, visibility: :under_development
    end
  end
end
