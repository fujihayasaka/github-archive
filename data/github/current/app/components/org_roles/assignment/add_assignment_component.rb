# typed: true
# frozen_string_literal: true

module OrgRoles
  module Assignment
    class AddAssignmentComponent < ApplicationComponent
      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(T::Array[Role]) }
      attr_reader :visible_roles

      sig { params(organization: Organization, visible_roles: T::Array[Role]).void.checked(:always).on_failure(:raise) }
      def initialize(organization:, visible_roles:)
        @organization = organization
        @visible_roles = visible_roles
      end

      def render?
        visible_roles.any?
      end
    end
  end
end
