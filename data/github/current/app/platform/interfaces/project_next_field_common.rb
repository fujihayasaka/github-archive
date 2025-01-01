# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectNextFieldCommon
      include Platform::Interfaces::Base
      PROJECT_NEXT_COHORT = "2022-04-18"
      description "Common fields across different field types"

      required_capabilities [:mobile_only_schema_mask]

      database_id_field

      created_at_field

      updated_at_field

      field :id, ID, description: "The Node ID of the ProjectNextFieldCommon object", method: :global_relay_id, null: false

      field :name, String, "The project field's name.", null: false

      field :project, Platform::Objects::ProjectNext, "The project that contains this field.", null: false, method: :async_memex_project

      field :settings, String, "The field's settings.", null: true

      def settings
        @object.settings.to_json
      end

      field :data_type, Platform::Enums::ProjectNextFieldType, "The field's type.", null: false
    end
  end
end
