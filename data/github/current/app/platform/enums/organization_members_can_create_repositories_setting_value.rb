# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationMembersCanCreateRepositoriesSettingValue < Platform::Enums::Base

      # Intended to represent settings values for the members can create
      # repositories setting on an organization:
      # - Public and private repositories
      # - Private repositories
      # - Internal repositories
      # - Disabled

      description "The possible values for the members can create repositories setting on an organization."

      value "ALL", "Members will be able to create public and private repositories."
      value "PRIVATE", "Members will be able to create only private repositories."
      value "INTERNAL", "Members will be able to create only internal repositories."
      value "DISABLED", "Members will not be able to create public or private repositories."
    end
  end
end
