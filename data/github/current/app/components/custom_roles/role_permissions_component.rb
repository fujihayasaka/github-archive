# typed: strict
# frozen_string_literal: true

module CustomRoles
  class RolePermissionsComponent < ApplicationComponent
    include GitHub::Memoizer

    sig { returns(T.any(EnterpriseRole, OrganizationRole)) }
    attr_reader :role

    sig { params(role: T.any(EnterpriseRole, OrganizationRole)).void }
    def initialize(role:)
      @role = role
      @permissions_loaded = T.let(false, T::Boolean)
    end

    sig { returns(T::Boolean) }
    memoize def empty?
      enterprise_permissions_by_category.empty? &&
        organization_permissions_by_category.empty? &&
        aggregate_repository_permissions_by_category.empty?
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def enterprise_permissions_by_category
      return {} unless enterprise_role

      load_permissions!
      EnterpriseFgpMetadata.for_role(enterprise_role)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def organization_permissions_by_category
      roles = [enterprise_role, organization_role].compact
      return {} if roles.empty?

      load_permissions!
      OrgFgpMetadata.for_roles(roles)
    end

    sig { returns(T.nilable(String)) }
    memoize def base_repository_role_name
      base_repository_role&.display_name
    end

    private

    sig { returns(T.nilable(EnterpriseRole)) }
    memoize def enterprise_role
      T.cast(role, EnterpriseRole) if role.is_a?(EnterpriseRole)
    end

    sig { returns(T.nilable(OrganizationRole)) }
    memoize def organization_role
      return T.cast(role, OrganizationRole) if role.is_a?(OrganizationRole)

      delegate_role = enterprise_role&.delegate_organization_role
      delegate_role if delegate_role.is_a?(OrganizationRole)
    end

    sig { returns(T.nilable(RepositoryRole)) }
    memoize def base_repository_role
      base_role = organization_role&.base_role
      base_role if base_role.is_a?(RepositoryRole)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def aggregate_repository_permissions_by_category
      roles = [organization_role, base_repository_role].compact
      return {} if roles.empty?

      load_permissions!
      RepoFgpMetadata.for_roles(roles)
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def base_repository_permissions_by_category
      return {} unless base_repository_role

      load_permissions!
      RepoFgpMetadata.for_role(base_repository_role)
    end

    # Returns repository permissions that are granted by the organization role beyond what the base role provides.
    #
    # While the base role's repo permissions should not be included in the org role's repo permissions by design,
    # this method takes a defensive approach by explicitly excluding base role permissions from the
    # organization role's repository permissions to ensure we never double-report a permission.
    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def additional_repository_permissions_by_category
      aggregate_repository_permissions_by_category.each_with_object({}) do |(category, all_permissions), memo|
        base_permissions = base_repository_permissions_by_category.fetch(category) { [] }
        additional_permissions = all_permissions - base_permissions
        next if additional_permissions.empty?

        memo[category] = additional_permissions
      end
    end

    sig { void }
    def load_permissions!
      return if @permissions_loaded

      GitHub::PrefillAssociations.prefill_associations(
        [enterprise_role, organization_role, base_repository_role],
        :permissions
      )

      @permissions_loaded = true
    end
  end
end
