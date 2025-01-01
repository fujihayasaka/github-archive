# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldLabelValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :labels

  def initialize(labels, item, field)
    super(item, field)
    @labels = labels
    @platform_type_name = "ProjectV2ItemFieldLabelValue"
  end
end
