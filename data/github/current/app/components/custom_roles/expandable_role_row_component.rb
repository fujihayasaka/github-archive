# typed: strict
# frozen_string_literal: true

module CustomRoles
  class ExpandableRoleRowComponent < ApplicationComponent
    sig { returns(T.any(EnterpriseRole, OrganizationRole)) }
    attr_reader :role

    sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
    attr_reader :system_arguments

    renders_one :action
    renders_one :description_prefix

    sig { params(role: T.any(EnterpriseRole, OrganizationRole), system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(role:, **system_arguments)
      @role = role
      @system_arguments = system_arguments
    end
  end
end
