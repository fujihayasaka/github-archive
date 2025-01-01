# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class TopicOrderField < Platform::Enums::Base
      description "Properties by which topic connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order topics by creation time", value: "created_at"
      value "UPDATED_AT", "Order topics by update time", value: "updated_at"
      value "NAME", "Order topics by name", value: "name"
    end
  end
end
