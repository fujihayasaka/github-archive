# typed: true
# frozen_string_literal: true

module Roles
  class DetailsComponent < ApplicationComponent
    include Orgs::RolesHelper
    attr_reader :role, :organization, :base_role, :repository

    def initialize(role:, organization:, base_role:, repository: nil)
      @role = role
      @organization = organization
      @base_role = base_role,
      @repository = repository
    end

    def show_base_role_badge?(role_name)
      @base_role == role_name
    end

    private

    def render?
      role.present? && organization.present? && organization.organization?
    end
  end
end
