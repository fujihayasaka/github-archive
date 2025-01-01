# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserListOrderField < Platform::Enums::Base
      mobile_only true
      description "Properties by which user list connections can be ordered."

      value "NAME", "Order user lists by name.", value: "slug"
      value "CREATED_AT", "Order user lists by creation time.", value: "created_at"
      value "LAST_ADDED_AT", "Order user lists by the last time an item was added.", value: "last_added_at"
    end
  end
end
