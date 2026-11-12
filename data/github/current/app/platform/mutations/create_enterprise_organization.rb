# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateEnterpriseOrganization < Platform::Mutations::Base
      class OwnerAssignmentPlan < T::Struct
        const :direct_owners, T::Array[User]
        const :invitees, T::Array[User]
      end

      description "Creates an organization as part of an enterprise account. User-authenticated requests make the viewer an owner. Users listed in `adminLogins` are invited as owners unless owner invitations are disabled, in which case they are added directly. Installation requests also add existing enterprise members directly. Invitation failures do not roll back organization creation. A personal access token used to create an organization is implicitly permitted to update the organization it created, if the organization is part of an enterprise that has SAML enabled or uses Enterprise Managed Users. If the organization is not part of such an enterprise, and instead has SAML enabled for it individually, the token will then require SAML authorization to continue working against that organization."
      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise owning the new organization.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of the new organization.", required: true
      argument :profile_name, String, "The profile name of the new organization.", required: true
      argument :billing_email, String, "The email used for sending billing receipts.", required: true
      argument :admin_logins,
        [String],
        "The logins of additional organization owners. Listed users are invited unless owner invitations are disabled, in which case they are added directly. Installation requests also add existing enterprise members directly.",
        required: true

      field :enterprise, Objects::Enterprise, "The enterprise that owns the created organization.", null: true
      field :organization, Objects::Organization, "The organization that was created.", null: true
      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :standard_authorization,
          permission: :create_enterprise_organizations,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(enterprise:, execution_errors:, **inputs)
        ensure_business_can_use_api!(enterprise)
        business_full_plan_required!(enterprise)

        viewer = context[:viewer]
        unless Authz.domain.check_allowed(viewer, :create_enterprise_organizations, enterprise)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create organizations for this enterprise.")
        end

        if enterprise.trial_org_creation_limit_reached?
          raise Errors::Forbidden.new(enterprise.trial_org_creation_limit_reached_message)
        end

        owner_assignment = owner_assignment_plan(
          enterprise: enterprise,
          viewer: viewer,
          admin_logins: inputs[:admin_logins],
        )
        inputs[:admin_logins] = owner_assignment.direct_owners.map(&:display_login)

        result = Organization::Creator.perform \
          context[:viewer],
          GitHub::Plan.free,
          inputs.merge(company_name: enterprise.name),
          business_owned: true,
          business: enterprise

        if result.success?
          invite_owners(
            organization: result.organization,
            inviter: viewer,
            authorization_actor: owner_assignment.direct_owners.first,
            invitees: owner_assignment.invitees,
            execution_errors: execution_errors,
          )

          {
            enterprise: enterprise,
            organization: result.organization,
          }
        else
          error_message = result.organization.errors.full_messages.to_sentence.presence
          error_message ||= result.error_message
          raise Errors::Unprocessable.new(error_message)
        end
      end

      private

      def owner_assignment_plan(enterprise:, viewer:, admin_logins:)
        proposed_admins = resolve_admins!(admin_logins)

        if viewer.bot? && proposed_admins.empty?
          raise Errors::Unprocessable.new("Must provide at least one valid owner")
        end

        if enterprise.bypass_admin_invites?
          direct_owners = viewer.bot? ? proposed_admins : ([viewer] + proposed_admins).uniq
          return OwnerAssignmentPlan.new(direct_owners: direct_owners, invitees: [])
        end

        unless viewer.bot?
          return OwnerAssignmentPlan.new(
            direct_owners: [viewer],
            invitees: proposed_admins.reject { |admin| admin == viewer },
          )
        end

        direct_owner_ids = enterprise.member_ids_for_organization_owner_assignment(
          user_ids: proposed_admins.map(&:id),
        ).to_set
        direct_owners = proposed_admins.select { |admin| direct_owner_ids.include?(admin.id) }

        if direct_owners.empty?
          raise Errors::Unprocessable.new("Must provide at least one valid owner who is an existing enterprise member")
        end

        OwnerAssignmentPlan.new(
          direct_owners: direct_owners,
          invitees: proposed_admins - direct_owners,
        )
      end

      def resolve_admins!(admin_logins)
        return [] if admin_logins.empty?

        users_by_login = User.with_logins(*admin_logins)
          .select(&:user?)
          .index_by { |user| user.display_login.downcase }
        missing_logins = admin_logins.reject do |login|
          users_by_login.key?(login.downcase)
        end

        if missing_logins.any?
          raise Errors::Unprocessable.new(
            "Could not resolve administrator logins: #{missing_logins.join(", ")}"
          )
        end

        resolved_admins = admin_logins.filter_map do |login|
          users_by_login[login.downcase]
        end
        resolved_admins.uniq
      end

      def invite_owners(organization:, inviter:, authorization_actor:, invitees:, execution_errors:)
        invitees.each do |invitee|
          invitation = OrganizationInviter.new(
            organization,
            actor: inviter,
            authorization_actor: authorization_actor,
            invitee: invitee,
            role: :admin,
            invitation_source: inviter.bot? ? :enterprise_organization_creation : :member,
          )
          next if invitation.invite_user

          message = invitation.error.presence || "The invitation could not be created."
          execution_errors.add(
            Errors::Unprocessable.new(
              "The organization was created, but #{invitee.display_login} could not be invited as an owner: #{message}"
            )
          )
        end
      end
    end
  end
end
