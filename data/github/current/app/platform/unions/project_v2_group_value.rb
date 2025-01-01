# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2GroupValue < Platform::Unions::Base
      description "Project group values"

      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::ProjectV2GroupAssigneeValue,
        Objects::ProjectV2GroupDateValue,
        Objects::ProjectV2GroupIssueTypeValue,
        Objects::ProjectV2GroupIterationValue,
        Objects::ProjectV2GroupMilestoneValue,
        Objects::ProjectV2GroupNumberValue,
        Objects::ProjectV2GroupRepositoryValue,
        Objects::ProjectV2GroupSingleSelectValue,
        Objects::ProjectV2GroupTextValue
      )
    end
  end
end
