# typed: true
# frozen_string_literal: true

module OrgRoles
  class RoleFilterComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T::Array[Role]) }
    attr_reader :custom_org_roles

    sig { returns(T::Hash[Symbol, String]) }
    attr_reader :query_hash

    sig do
      params(
        custom_org_roles: T::Array[Role],
        query_hash: T::Hash[Symbol, String],
      ).void.checked(:always).on_failure(:raise)
    end
    def initialize(custom_org_roles:, query_hash:)
      @custom_org_roles = custom_org_roles
      @query_hash = query_hash
    end

    sig { params(filter: T::Hash[Symbol, String]).returns(String) }
    def get_query(filter: {})
      OrganizationRole.stringify_query_hash(@query_hash.merge(filter))
    end
  end
end
