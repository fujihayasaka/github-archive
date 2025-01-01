# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2SingleSelectField < Platform::Objects::Base
      extend T::Helpers
      description "A single select field inside a project."

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
        delegate :load_from_global_id, to: Models::SingleSelectField
      end

      Platform::Helpers::ProjectV2Field
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTSSF", :opvtssf, :upvtssf)
        )
        .call(self)

      field(:options, [Objects::ProjectV2SingleSelectFieldOption, null: false],
        description: "Options for the single select field",
        null: false,
      ) do
        T.bind(self, GraphQL::Schema::Field)
        argument :names, [String], "Filter returned options to only those matching these names, case " \
          "insensitive.", required: false
      end

      def options(names: nil)
        ArrayWrapper.new(@object.options(names: names))
      end
    end
  end
end
