# typed: strict
# frozen_string_literal: true

module OrgRoles
  class SystemRolesComponent < ApplicationComponent
    extend T::Sig

    sig { returns(Organization) }
    attr_reader :organization

    sig { returns(T.untyped) }
    attr_reader :system_arguments

    sig { params(organization: Organization, system_arguments: T.untyped).void }
    def initialize(organization:, **system_arguments)
      @organization = organization
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
        .sorted_visible_preset_roles(organization)
    end
  end
end
