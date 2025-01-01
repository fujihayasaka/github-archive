# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectGroupValue
  attr_reader :group

  delegate :value, to: :group

  def initialize(group:)
    raise Platform::Errors::Internal, "group is required"  unless group

    @group = group
  end

  def platform_type_name
    "ProjectV2Group#{group.column.data_type.classify}Value"
  end

  def async_memex_project
    Platform::Loaders::ActiveRecord.load(MemexProject, group.column.memex_project_id)
  end
end
