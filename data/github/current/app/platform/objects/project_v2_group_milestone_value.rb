# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupMilestoneValue < Platform::Objects::Base
      description "Value when a view is grouped by a milestone column"
      minimum_accepted_scopes ["read:org"]
      mobile_only true

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      field :title, String, "The title of the milestone shared by all the items for the grouped field", null: true, method: :value
    end
  end
end
