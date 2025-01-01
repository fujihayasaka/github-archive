# typed: strict
# frozen_string_literal: true

module CustomRoles
  class ExpandableRoleRowComponent < ApplicationComponent
    sig { returns(Role) }
    attr_reader :role

    sig { returns(T.untyped) }
    attr_reader :system_arguments

    renders_one :action

    sig { params(role: Role, system_arguments: T.untyped).void }
    def initialize(role:, **system_arguments)
      @role = role
      @system_arguments = system_arguments
    end

    private

    sig { returns(T.class_of(ApplicationComponent)) }
    def permissions_component_class
      if role.is_a?(OrganizationRole)
        CustomRoles::OrgRolePermissionsComponent
      else
        raise ArgumentError, "Only OrganizationRole is supported at the moment"
      end
    end
  end
end
