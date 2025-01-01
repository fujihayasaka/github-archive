# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldUserValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :users

  def initialize(users, item, field)
    super(item, field)
    @users = users
    @platform_type_name = "ProjectV2ItemFieldUserValue"
  end
end
