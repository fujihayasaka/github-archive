# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldMilestoneValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :milestone

  def initialize(milestone, item, field)
    super(item, field)
    @milestone = milestone
    @platform_type_name = "ProjectV2ItemFieldMilestoneValue"
  end
end
