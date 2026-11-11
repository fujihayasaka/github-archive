# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IpAllowListEntryOrderField < Platform::Enums::Base
      description "Properties by which IP allow list entry connections can be ordered."

      value "CREATED_AT", "Order IP allow list entries by creation time.", value: "created_at"
      value "ALLOW_LIST_VALUE", "Order IP allow list entries by the allow list value.", value: "allow_list_value"
    end
  end
end
