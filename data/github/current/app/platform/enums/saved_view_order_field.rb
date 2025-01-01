# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SavedViewOrderField < Platform::Enums::Base
      description "Properties by which saved view connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order saved views by creation time", value: "created_at"
      value "UPDATED_AT", "Order saved views by update time", value: "updated_at"
    end
  end
end
