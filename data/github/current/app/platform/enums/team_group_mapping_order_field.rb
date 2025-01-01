# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamGroupMappingOrderField < Platform::Enums::Base
      visibility :under_development
      description "Properties by which team group mappings connections can be ordered."

      value "ID", "Order group mappings by ID", value: "id"
      value "GROUP_ID", "Order group mappings by group ID", value: "group_id"
      value "GROUP_NAME", "Order group mappings by group name", value: "group_name"
      value "SYNCED_AT", "Order group mappings by sync timestamp", value: "synced_at"
      value "CREATED_AT", "Order group mappings by creation timestamp", value: "created_at"
    end
  end
end
