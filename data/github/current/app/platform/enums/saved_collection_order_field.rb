# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SavedCollectionOrderField < Platform::Enums::Base
      description "Properties by which saved collection connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order saved collections by creation time", value: "created_at"
      value "UPDATED_AT", "Order saved collections by update time", value: "updated_at"
    end
  end
end
