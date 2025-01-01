# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class OrganizationEnterpriseOwners < Resolvers::Base
      type Connections::OrganizationEnterpriseOwner, null: false

      argument :query, String, "The search string to look for.", required: false
      argument :organization_role, Enums::RoleInOrganization, "The organization role to filter by.", required: false
      argument :order_by, Inputs::OrgEnterpriseOwnerOrder,
        "Ordering options for enterprise owners returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }

      def resolve(query: nil, organization_role: nil, order_by: nil)
        object.async_business.then do |business|
          if business && context[:permission].can_list_private_org_members?(object) # Make sure the business exists, and the user has access
            ensure_business_not_suspended!(business)
            if query_unaffiliated_owners?(organization_role)
              # Get all of the enterprise owners that are not owners and not members of the organization
              object.async_unaffiliated_enterprise_owners(query: query, order_by: order_by).then do |owners|
                owners
              end
            elsif query_membership_role?(organization_role)
              # Get all of the enterprise owners given a specific organization role
              object.async_affiliated_enterprise_owners(people_query: people_query(query, viewer_role(organization_role)),
                                                        order_by: order_by).then do |owners|
                owners
              end
            else
              # Don't filter by organization role, return all matching enterprise owners
              object.async_enterprise_owners(query: query, order_by: order_by).then do |owners|
                owners
              end
            end
          else
            User.none
          end
        end
      end

      private

      def people_query(query, role)
        Organization::People::Query.new(
          query: "role:#{role} #{query}",
          organization: object,
          current_user: context[:viewer],
          role: role)
      end

      def viewer_role(role)
        # Get the string value of the role to be passed into the query
        # Platform::Enums::RoleInOrganization returns "direct_member" but
        # ::Business#filtered_organizations expects "member"
        return "member" if role == "direct_member"
        return "owner" if role == "owner"
        nil
      end

      def query_unaffiliated_owners?(organization_role)
        organization_role == "unaffiliated"
      end

      def query_membership_role?(organization_role)
        organization_role == "owner" || organization_role == "direct_member"
      end
    end
  end
end
