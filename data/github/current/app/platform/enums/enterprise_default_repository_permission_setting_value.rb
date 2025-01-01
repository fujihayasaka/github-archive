# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseDefaultRepositoryPermissionSettingValue < Platform::Enums::Base

      # Intended to represent settings values for the enterprise base repository
      # permission setting:
      # - No policy
      # - Admin
      # - Write
      # - Read
      # - No permission

      description "The possible values for the enterprise base repository permission setting."

      value "NO_POLICY", "Organizations in the enterprise choose base repository permissions for their members."
      value "ADMIN", "Organization members will be able to clone, pull, push, and add new collaborators to all organization repositories."
      value "WRITE", "Organization members will be able to clone, pull, and push all organization repositories."
      value "READ", "Organization members will be able to clone and pull all organization repositories."
      value "NONE", "Organization members will only be able to clone and pull public repositories."
    end
  end
end
