# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApproveVerifiableDomain < Platform::Mutations::Base
      description "Approve a verifiable domain for notification delivery."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      visibility :public, environments: [:enterprise, :dotcom]

      argument :id, ID, "The ID of the verifiable domain to approve.", required: true, loads: Objects::VerifiableDomain, as: :domain

      field :domain, Objects::VerifiableDomain, "The verifiable domain that was approved.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, domain:, **inputs)
        owner = domain.owner
        if owner.is_a?(::Business)
          permission.access_allowed?(:administer_business,
            resource: owner, repo: nil, organization: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        elsif owner.is_a?(::Organization)
          permission.access_allowed?(:v4_manage_org_users,
            resource: owner, organization: owner, current_repo: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(domain:, **inputs)
        viewer = context[:viewer]

        unless domain.adminable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} is not authorized to approve this domain.")
        end

        if domain && domain.approve(actor: viewer)
          { domain: domain }
        else
          raise Errors::Unprocessable.new(domain.errors.full_messages.join(", "))
        end
      end
    end
  end
end
