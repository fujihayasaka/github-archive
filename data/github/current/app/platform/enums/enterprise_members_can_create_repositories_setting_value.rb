# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseMembersCanCreateRepositoriesSettingValue < Platform::Enums::Base

      # Intended to represent settings values for the members can create
      # repositories setting:
      # - No policy
      # - Public and private repositories
      # - Private repositories
      # - Disabled

      description "The possible values for the enterprise members can create repositories setting."

      value "NO_POLICY", "Organization owners choose whether to allow members to create repositories."
      value "ALL", "Members will be able to create public and private repositories."
      value "PUBLIC", "Members will be able to create only public repositories."
      value "PRIVATE", "Members will be able to create only private repositories."
      value "DISABLED", "Members will not be able to create public or private repositories."
    end
  end
end
