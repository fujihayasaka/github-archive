# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserStatusOrderField < Platform::Enums::Base
      description "Properties by which user status connections can be ordered."

      value "UPDATED_AT", "Order user statuses by when they were updated.", value: "updated_at"
    end
  end
end
