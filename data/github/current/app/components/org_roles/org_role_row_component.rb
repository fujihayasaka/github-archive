# typed: strict
# frozen_string_literal: true

module OrgRoles
  class OrgRoleRowComponent < ApplicationComponent
    include GitHub::Memoizer
    extend T::Sig

    sig { returns(OrganizationRole) }
    attr_reader :role

    sig { returns(T.untyped) }
    attr_reader :system_arguments

    renders_one :action_menu

    sig { params(role: OrganizationRole, system_arguments: T.untyped).void }
    def initialize(role:, **system_arguments)
      @role = role
      @system_arguments = system_arguments
    end

    private

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def org_fgp_metadata
      OrgFgpMetadata.for_role(role)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def repo_fgp_metadata
      # A role must have a base repo role to have repo FGPs
      return {} if base_repo_role.nil?

      FgpMetadata.for_role(role)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def base_repo_role_fgp_metadata
      return {} if base_repo_role.nil?

      FgpMetadata.for_role(base_repo_role)
    end

    sig { returns(T.nilable(Role)) }
    def base_repo_role
      role.base_role
    end
  end
end
