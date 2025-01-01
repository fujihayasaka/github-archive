# typed: strict
# frozen_string_literal: true

module CustomRoles
  class OrgRolePermissionsComponent < ApplicationComponent
    include GitHub::Memoizer

    sig { returns(OrganizationRole) }
    attr_reader :role

    sig { params(role: OrganizationRole).void }
    def initialize(role:)
      @role = role
    end

    private

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def org_fgp_metadata
      OrgFgpMetadata.for_role(role)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def repo_fgp_metadata
      return {} if base_repo_role.nil? # A role must have a base repo role to have repo FGPs

      RepoFgpMetadata.for_role(role)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def base_repo_role_fgp_metadata
      return {} if base_repo_role.nil?

      RepoFgpMetadata.for_role(base_repo_role)
    end

    sig { returns(T.nilable(Role)) }
    def base_repo_role
      role.base_role
    end
  end
end
