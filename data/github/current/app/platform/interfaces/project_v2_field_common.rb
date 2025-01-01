# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectV2FieldCommon
      include Platform::Interfaces::Base
      description "Common fields across different project field types"

      visibility :public, environments: [:dotcom, :enterprise]

      database_id_field

      created_at_field

      updated_at_field

      field :id, ID, description: "The Node ID of the ProjectV2FieldCommon object", method: :global_relay_id, null: false

      field :name, String, "The project field's name.", null: false

      field :project, Platform::Objects::ProjectV2, "The project that contains this field.", null: false, method: :async_memex_project

      field :data_type, Platform::Enums::ProjectV2FieldType, "The field's type.", null: false

      field :is_issue_field, Boolean, feature_flag: IssueFieldsFeature::ISSUE_FIELDS_FLAG, description: "Returns true if this field is associated with an organization issue field", null: false, method: :issue_field?
    end
  end
end
