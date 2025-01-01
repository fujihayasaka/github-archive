# typed: true
# frozen_string_literal: true

module Roles
  class ListComponent < ApplicationComponent
    include Orgs::RolesHelper
    attr_reader :organization, :repository

    def initialize(organization:, repository: nil)
      @organization = organization
      @repository = repository
    end

    def base_role
      organization_base_role(organization: organization)
    end

    private

    def render?
      organization.present? && organization.organization?
    end

    memoize def organization_role_list
      roles = organization.custom_repo_roles
      default_roles = system_roles

      org_and_system_roles = roles + default_roles
      GitHub::PrefillAssociations.prefill_associations(org_and_system_roles, :base_role)
      { org_roles: roles, system_roles: default_roles }
    end
  end
end
