# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Exposes BusinessTeam as EnterpriseTeam in the GraphQL schema.
    # Pattern: model_name points to the Ruby model, class name is the public API name.
    class EnterpriseTeam < Platform::Objects::Base
      docs_category :enterprise_admin
      model_name "BusinessTeam"

      description "A team that belongs to an enterprise and can be assigned to multiple organizations."
      docs_category :enterprise_admin

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      implements Interfaces::TeamReviewRequestable

      implements_node templates: [[:et, :enterprise_id, :id]], as: "ET", ready_date: "2026-03-10" do |et|
        {
          prefix: :et,
          enterprise_id: et.business_id,
          id: et.id }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_business.then do |business|
          permission.access_allowed?(
            :site_admin_authorization,
            permission: :read_enterprise_members,
            resource: business,
            repo: nil,
            organization: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_business.then do |business|
          next Promise.resolve(false) if business.nil?
          next Promise.resolve(true) if GitHub.enterprise? && permission.viewer&.site_admin?
          # Business membership is the same for all teams — cache it per business+viewer
          business.async_member?(permission.viewer)
        end
      end

      field :enterprise, Objects::Enterprise,
        description: "The enterprise this team belongs to.",
        null: true

      def enterprise
        @object.async_business
      end

      field :assigned_organizations, Connections::EnterpriseTeamAssignedOrganization,
        description: "Organizations this team is assigned to.",
        null: false,
        connection: true do
          argument :order_by, Inputs::EnterpriseTeamOrganizationOrder,
            "Ordering options for organizations returned from the connection.",
            required: false, default_value: { field: "id", direction: "ASC" }
        end

      def assigned_organizations(**arguments)
        scope = if @object.org_assignment_all?
          @object.business.organizations.merge(::Organization.active)
        elsif @object.org_assignment_selected?
          @object.selected_organizations
        else
          ::Organization.none
        end

        if (ordering = arguments[:order_by])
          unless ordering[:field] == "id" && ordering[:direction].to_s.casecmp("asc").zero?
            scope = scope.order(ordering[:field] => ordering[:direction])
          end
        end

        scope
      end

      field :organization_selection_type, Enums::EnterpriseTeamOrganizationSelectionType,
        description: "How this team selects its associated organizations.",
        null: false,
        method: :organization_selection_type

      field :name, String, description: "The name of the team.", null: false
      field :description, String, description: "The description of the team.", null: true
      field :slug, String, description: "The slug corresponding to the team.", null: false
      field :combined_slug, String, description: "The human-readable, unique identifier for the enterprise and team.", null: false
      field :privacy, Enums::TeamPrivacy, description: "The level of privacy the team has.", null: false
      field :notification_setting, Enums::TeamNotificationSetting,
        description: "Whether the team will receive notifications when mentioned.", null: false

      field :enterprise_team_members, Connections::EnterpriseTeamMember, description: "A list of users who are members of this enterprise team.", null: false, connection: false do
        has_connection_arguments
        argument :query, String, "The search string to look for.", required: false
        argument :order_by, Inputs::EnterpriseTeamMemberOrder, "Order for the connection.", required: false,
          default_value: { field: "id", direction: "ASC" }
      end

      def enterprise_team_members(**arguments)
        if arguments[:first].nil? && arguments[:last].nil?
          arguments[:first] = Schema::DEFAULT_MAX_PER_PAGE
        end
        Platform::ConnectionWrappers::EnterpriseTeamMembers.new(
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

      full_database_id_field
      created_at_field
      updated_at_field

      field :is_viewer_member, Boolean,
        description: "Whether the viewer is a member of this team.",
        null: false

      def is_viewer_member
        @object.async_member?(context[:viewer])
      end

      field :viewer_can_administer, Boolean,
        description: "Whether the viewer can administer this team.",
        null: false

      def viewer_can_administer
        @object.async_adminable_by?(@context[:viewer])
      end
    end
  end
end
