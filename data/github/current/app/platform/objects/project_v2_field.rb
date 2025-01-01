# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2Field < Platform::Objects::Base
      description "A field inside a project."

      class << self
        # Delegate static methods to the ProjectV2Field helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      # Call the generic definition method and invoke the returned block.
      # This will invoke methods in the Platform base object DSL that are
      # shared between all field types.
      Platform::Helpers::ProjectV2Field
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTF", :opvtf, :upvtf)
        )
        .call(self)
    end
  end
end
