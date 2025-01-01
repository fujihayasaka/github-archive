# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2IterationField < Platform::Objects::Base
      description "An iteration field inside a project."

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      Platform::Helpers::ProjectV2Field
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTIF", :opvtif, :upvtif)
        )
        .call(self)

      field :configuration, Objects::ProjectV2IterationFieldConfiguration, "Iteration configuration settings", null: false

      def self.load_from_global_id(id)
        Models::IterationField.load_from_global_id(id)
      end
    end
  end
end
