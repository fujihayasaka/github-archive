# typed: strict
# frozen_string_literal: true

module OrgRoles
  class SystemRolesComponent < ApplicationComponent
    sig { returns(T.any(Organization, Business)) }
    attr_reader :owner

    sig { returns(T.untyped) }
    attr_reader :system_arguments

    sig { params(owner: T.any(Organization, Business), system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(owner:, **system_arguments)
      @owner = owner
      @system_arguments = system_arguments
    end

    private

    sig { returns(T::Boolean) }
    def render?
      roles.any?
    end

    sig { returns(T::Array[OrganizationRole]) }
    memoize def roles
      T.unsafe(OrganizationRole.includes(:permissions).includes(base_role: :permissions))
        .sorted_visible_preset_roles(owner)
    end
  end
end
