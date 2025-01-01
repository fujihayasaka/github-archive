# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationInvitation < Platform::Objects::Base
      description "An Invitation for a user to an organization."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, org_invitation)
        org_invitation.async_organization.then do |org|
          next true if permission.access_allowed?(
            :v4_read_org_invitations,
            resource: org,
            current_org: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )

          org.async_business.then do |business|
            next true if permission.access_allowed?(:view_enterprise_external_identities_read_only, resource: business, current_org: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)

            if org && org.feature_enabled?(:teams_cap_updates)
              # Allow team maintainers who are not org admins to see pending invitations for the teams they maintain
              Loaders::ActiveRecord.load(::TeamInvitation, org_invitation.id, column: :organization_invitation_id).then do |team_invitation|
                team_invitation&.async_team.then do |team|
                  actor_id = permission.viewer&.id || permission.actor&.id
                  next true if team && actor_id && team.maintainers.exists?(id: actor_id)
                end
              end
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer.site_admin?

        object.async_organization.then do |org|
          org.async_adminable_by?(permission.viewer).then do |org_adminable|
            next true if org_adminable
            if permission.viewer.try(:installation)
              next true if org.resources.members.readable_by?(permission.viewer)
              next true if org.resources.organization_administration.readable_by?(permission.viewer)
            end

            org.async_business.then do |business|
              next true if business&.owner?(permission.viewer)

              object.async_teams.then do |teams|
                Promise
                  .all(teams.map { |single_team| single_team.async_adminable_by?(permission.viewer) })
                  .then { |team_adminables| team_adminables.any? }
              end
            end
          end
        end
      end

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      implements_node templates: [[:oi, :org_id, :organization_invitation_id]], as: "OI", ready_date: "2021-06-24" do |organization_invitation|
        organization_invitation.async_organization.then do |org|
          {
            prefix: :oi,
            org_id: org.id,
            organization_invitation_id: organization_invitation.id
          }
        end
      end

      database_id_field(visibility: :internal)

      created_at_field

      field :organization, Objects::Organization, method: :async_organization, description: "The organization the invite is for", null: false

      field :email, String, description: "The email address of the user invited to the organization.", null: true

      def email
        return @object.email unless @object.email.nil?
        @object.async_invitee.then do |invitee|
          invitee.async_profile.then do |profile|
            profile&.email.presence
          end
        end
      end

      field :invitation_type, Enums::OrganizationInvitationType, description: "The type of invitation that was sent (e.g. email, user).", null: false

      def invitation_type
        @object.email.present? ? :email : :user
      end

      field :role, Enums::OrganizationInvitationRole, "The user's pending role in the organization (e.g. member, owner).", null: false

      field :invitation_source, Enums::OrganizationInvitationSource, "The source of the invitation.", null: false

      field :inviter,
        Objects::User,
        method: :async_inviter,
        description: "The user who created the invitation.",
        null: false do
        deprecated(
          start_date: Date.new(2024, 1, 8),
          reason: "`inviter` will be removed.",
          superseded_by: "`inviter` will be replaced by `inviterActor`.",
          owner: "jdennes",
        )
      end

      field :inviter_actor,
        Objects::User,
        method: :async_inviter,
        description: "The user who created the invitation.",
        null: true

      field :invitee, Objects::User, method: :async_invitee, description: "The user who was invited to the organization.", null: true

      field :teams, Connections.define(Objects::Team), numeric_pagination_enabled: true, visibility: :internal, description: "A list of teams the user will be added to", null: false, connection: true

      def teams(**numeric_pagination_args)
        @object.teams.scoped
      end
    end
  end
end
