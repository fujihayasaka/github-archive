# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationAdminInfo < Platform::Objects::Base
      description "Organization information only visible to members"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # See if viewer is an admin of the org or a site admin
        object.org.adminable_by?(permission.viewer) || Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["read:org"]

      field :members_can_create_repositories, Boolean, description: "ability for organization org members to create repositories", null: false

      def members_can_create_repositories
        @object.org.members_can_create_repositories?
      end

      field :members_can_create_public_repositories, Boolean, description: "ability for organization org members to create public repositories", null: false

      def members_can_create_public_repositories
        @object.org.members_can_create_public_repositories?
      end

      field :default_repository_permission, Enums::DefaultRepositoryPermissionField, description: "Base repository permission for organization members", null: false

      def default_repository_permission
        Platform::Loaders::Configuration.load(@object.org, :default_repository_permission_name)
      end

      field :invitations, Connections.define(Objects::OrganizationInvitation), description: "A list of pending invitations for users to this organization", null: true, connection: true

      def invitations
        @object.org.pending_invitations.scoped
      end

      field :outside_collaborators, Connections.define(Objects::User), description: "A list of users who are outside collaborators of this organization.", null: true, connection: true

      def outside_collaborators
        @object.org.outside_collaborators.scoped.filter_spam_for(@context[:viewer])
      end

      field :enterprise_server_installations, Connections.define(Objects::EnterpriseServerInstallation),
        description: "Enterprise Server installations owned by the organization.",
        visibility: {
          internal: { environments: [:enterprise] },
          under_development: { environments: [:dotcom] },
        },
        connection: true, null: false do

        argument :order_by, Inputs::EnterpriseServerInstallationOrder,
          "Ordering options for Enterprise Server installations returned.",
          required: false, default_value: { field: "host_name", direction: "ASC" }
      end

      def enterprise_server_installations(order_by: nil)
        installations = object.org.enterprise_installations
        unless order_by.nil?
          installations = installations.order "enterprise_installations.#{order_by[:field]} #{order_by[:direction]}"
        end
        installations
      end
    end
  end
end
