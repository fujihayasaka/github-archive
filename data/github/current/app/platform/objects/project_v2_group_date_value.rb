# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupDateValue < Platform::Objects::Base
      description "Value when a view is grouped by a date column"
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      field :date, Scalars::Date, "The ISO 8601 date value shared by all the items for the grouped field", null: true, method: :value
    end
  end
end
