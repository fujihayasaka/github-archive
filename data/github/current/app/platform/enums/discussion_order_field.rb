# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionOrderField < Platform::Enums::Base
      description "Properties by which discussion connections can be ordered."

      value "CREATED_AT", "Order discussions by creation time.", value: "created_at"
      value "UPDATED_AT", "Order discussions by most recent modification time.", value: "bumped_at"
    end
  end
end
