# typed: true
# frozen_string_literal: true

module OrgRoles
  class SearchComponent < ApplicationComponent
    sig { returns(String) }
    attr_reader :url

    sig { returns(String) }
    attr_reader :query

    sig do
      params(
        query: String,
        url: String,
        organization: Organization,
        org_roles: T::Array[OrganizationRole]
     ).void.checked(:always).on_failure(:raise)
    end
    def initialize(query:, url:, organization:, org_roles:)
      @query = query
      @url = url
      @organization = organization
      @org_roles = org_roles
    end

    private

    memoize def suggestable_roles
      defined_custom_org_roles = @org_roles.map do |role|
        {
          value: "#{role.name}"
        }
      end
      defined_custom_org_roles.to_json
    end
  end
end
