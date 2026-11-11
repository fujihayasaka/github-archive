# typed: strict
# frozen_string_literal: true

module Targeting
  # A set of attributes that can be targeted by conditions
  class Attribute < T::Enum
    enums do
      RefName = new("ref_name")
      Repository = new("repository")
      RepositoryGlobalId = new("repository_global_id")
      RepositoryName = new("repository_name")
      RepositoryCustomProperties = new("repository_custom_properties")
      RepositorySystemProperties = new("repository_system_properties")
      OrganizationCustomProperties = new("organization_custom_properties")
      Organization = new("organization")
      OrganizationName = new("organization.name")
      Enterprise = new("enterprise")
      User = new("user")
    end
  end
end
