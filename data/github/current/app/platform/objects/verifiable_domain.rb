# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class VerifiableDomain < Platform::Objects::Base
      description "A domain that can be verified or approved for an organization or an enterprise."

      visibility :public, environments: [:enterprise, :dotcom]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, domain)
        return true if permission.viewer && permission.viewer.site_admin?
        domain.async_owner.then do |owner|
          case owner
          when ::Business
            permission.access_allowed?(
              :administer_business, resource: owner, organization: nil, current_repo: nil,
              allow_integrations: false, allow_user_via_granular_actor: false)
          when ::Organization
            permission.access_allowed?(
              :v4_manage_org_users, resource: owner, organization: owner, current_repo: nil,
              allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer && permission.viewer.site_admin?

        object.async_owner.then do |owner|
          case owner
          when ::Business
            owner.owner?(permission.viewer)
          when ::Organization
            owner.async_adminable_by?(permission.viewer).then do |org_adminable|
              next true if org_adminable
              if permission.viewer.try(:installation)
                next true if owner.resources.organization_administration.readable_by?(permission.viewer)
                next true if owner.resources.members.readable_by?(permission.viewer)
              end
            end
          end
        end
      end

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      implements_node templates: [[:b, :business_id, :id], [:o, :org_id, :id]], as: "VD", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |verifiable_domain|
        case verifiable_domain.owner_type
        when "Business"
          { prefix: :b, business_id: verifiable_domain.owner_id, id: verifiable_domain.id }
        when "User"
          { prefix: :o, org_id: verifiable_domain.owner_id, id: verifiable_domain.id }
        else
          raise Platform::Errors::Internal, "Unexpected verifiable_domain owner_type: #{verifiable_domain.owner_type.inspect}"
        end
      end

      database_id_field
      field :domain, Scalars::URI, "The unicode encoded domain.", null: false
      created_at_field
      updated_at_field
      field :punycode_encoded_domain, Scalars::URI, description: "The punycode encoded domain.", null: false
      field :is_verified, Boolean, "Whether or not the domain is verified.", null: false, method: :verified?
      field :is_approved, Boolean, "Whether or not the domain is approved.", null: false, method: :approved?
      field :owner, Unions::VerifiableDomainOwner, description: "The owner of the domain.", null: false, method: :async_owner
      field :verification_token, String, description: "The current verification token for the domain.", null: true, method: :async_verification_token
      field :dns_host_name, Scalars::URI, description: "The DNS host name that should be used for verification.", null: true, method: :async_dns_host_name
      field :token_expiration_time, Scalars::DateTime, description: "The time that the current verification token will expire.", null: true, method: :async_token_expiration_time
      field :has_found_host_name, Boolean, description: "Whether a TXT record for verification with the expected host name was found.", null: false, method: :async_host_name_found?
      field :has_found_verification_token, Boolean, description: "Whether a TXT record for verification with the expected verification token was found.", null: false, method: :async_verification_token_found?
      field :is_required_for_policy_enforcement, Boolean, description: "Whether this domain is required to exist for an organization or enterprise policy to be enforced.", null: false, method: :async_required_for_policy_enforcement?
    end
  end
end
