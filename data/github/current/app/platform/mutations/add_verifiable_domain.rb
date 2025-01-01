# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddVerifiableDomain < Platform::Mutations::Base
      description "Adds a verifiable domain to an owning account."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      visibility :public, environments: [:enterprise, :dotcom]

      argument :owner_id, ID, "The ID of the owner to add the domain to", required: true, loads: Unions::VerifiableDomainOwner
      argument :domain, Scalars::URI, "The URL of the domain", required: true

      field :domain, Objects::VerifiableDomain, "The verifiable domain that was added.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
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

      def resolve(owner:, **inputs)
        viewer = context[:viewer]

        unless owner.adminable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to add a domain to this #{owner_description(owner)}.")
        end

        domain = owner.verifiable_domains.build(domain: inputs[:domain])
        if domain.save
          { domain: domain }
        else
          raise Errors::Unprocessable.new(domain.errors.full_messages.join(", "))
        end
      end

      private

      def owner_description(owner)
        owner.is_a?(::Business) ? "enterprise account" : "organization"
      end
    end
  end
end
