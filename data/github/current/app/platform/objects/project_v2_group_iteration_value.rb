# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupIterationValue < Platform::Objects::Base
      description "Value when a view is grouped by an iteration column"
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      field :iteration_id, String, "The iteration ID shared by all the items for the grouped field", null: true, method: :value
    end
  end
end
