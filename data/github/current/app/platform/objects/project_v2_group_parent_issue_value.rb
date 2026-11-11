# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupParentIssueValue < Platform::Objects::Base
      description "Value when a view is grouped by parent issue"
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      field :title_with_nwo,
        String,
        "The title, repository owner, repository name and the number of the parent issue shared by all the items for the grouped field",
        null: true,
        method: :value
    end
  end
end
