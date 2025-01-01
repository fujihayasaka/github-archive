# typed: strict
# frozen_string_literal: true

module CustomRoles
  class ExpandableRoleRowComponent < ApplicationComponent
    sig { returns(T.any(EnterpriseRole, OrganizationRole)) }
    attr_reader :role

    sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
    attr_reader :system_arguments

    renders_one :action

    sig { params(role: T.any(EnterpriseRole, OrganizationRole), system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(role:, **system_arguments)
      @role = role
      @system_arguments = system_arguments
    end

    private

    sig { returns(T.class_of(ApplicationComponent)) }
    def permissions_component_class
      if current_user.feature_enabled?(:shared_role_permissions_component)
        return CustomRoles::RolePermissionsComponent
      end

      case role
      when OrganizationRole
        CustomRoles::OrgRolePermissionsComponent
      when EnterpriseRole
        CustomRoles::EnterpriseRolePermissionsComponent
      end
    end
  end
end
