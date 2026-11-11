# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AppOrderField < Platform::Enums::Base
      description "Properties by which app connections can be ordered."

      visibility :internal

      value "CREATED_AT", "Order apps by creation time.", value: "created_at"
      value "UPDATED_AT", "Order apps by update time.", value: "updated_at"
    end
  end
end
