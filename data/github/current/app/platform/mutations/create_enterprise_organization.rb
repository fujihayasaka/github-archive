# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateEnterpriseOrganization < Platform::Mutations::Base
      description "Creates an organization as part of an enterprise account. A personal access token used to create an organization is implicitly permitted to update the organization it created, if the organization is part of an enterprise that has SAML enabled or uses Enterprise Managed Users. If the organization is not part of such an enterprise, and instead has SAML enabled for it individually, the token will then require SAML authorization to continue working against that organization."
      minimum_accepted_scopes ["admin:enterprise"]


      argument :enterprise_id, ID, "The ID of the enterprise owning the new organization.", required: true, loads: Objects::Enterprise
      argument :login, String, "The login of the new organization.", required: true
      argument :profile_name, String, "The profile name of the new organization.", required: true
      argument :billing_email, String, "The email used for sending billing receipts.", required: true
      argument :admin_logins, [String], "The logins for the administrators of the new organization.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise that owns the created organization.", null: true
      field :organization, Objects::Organization, "The organization that was created.", null: true

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

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)
        business_full_plan_required!(enterprise)

        viewer = context[:viewer]
        unless Authz.domain.check_allowed(viewer, :create_enterprise_organizations, enterprise)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create organizations for this enterprise.")
        end

        if enterprise.trial_org_creation_limit_reached?
          raise Errors::Forbidden.new("Upgrade to Enterprise to create more organizations.")
        end

        result = Organization::Creator.perform \
          context[:viewer],
          GitHub::Plan.free,
          inputs.merge(company_name: enterprise.name),
          business_owned: true,
          business: enterprise

        if result.success?
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
    end
  end
end
