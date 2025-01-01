# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupRepositoryValue < Platform::Objects::Base
      description "Value when a view is grouped by a repository column"
      minimum_accepted_scopes ["read:org"]
      mobile_only true

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      field :name_with_owner, String, "The name (with owner) of the repository shared by all the items for the grouped field", null: true, method: :value
    end
  end
end
