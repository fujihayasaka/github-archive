# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldGroup
  attr_reader :group,
              :view,
              :platform_type_name,
              :value

  delegate :view_group_id, to: :group

  def initialize(view:, group:, v2: true)
    raise Platform::Errors::Internal, "view is required"  unless view
    raise Platform::Errors::Internal, "group is required" unless group

    @group              = group
    @view               = view
    @platform_type_name = v2 ? "ProjectV2ItemFieldGroup" : "ProjectNextItemFieldGroup"
    @value              = group.column ? Platform::Models::ProjectGroupValue.new(group: group) : nil
  end

  def field
    group.column
  end

  def title
    if group.column && group.title.blank?
      "No #{group.column_name}"
    else
      group.title.to_s.dup.force_encoding("utf-8")
    end
  end
end
