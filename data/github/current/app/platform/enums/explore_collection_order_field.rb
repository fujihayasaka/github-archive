# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ExploreCollectionOrderField < Platform::Enums::Base
      description "Properties by which collection connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order collection by creation time", value: "created_at"
      value "UPDATED_AT", "Order collection by update time", value: "updated_at"
      value "DISPLAY_NAME", "Order collection by display name", value: "display_name"
    end
  end
end
