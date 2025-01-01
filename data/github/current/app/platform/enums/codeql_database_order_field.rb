# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CodeqlDatabaseOrderField < Platform::Enums::Base
      description "Properties by which CodeQL database connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order CodeQL databases by creation time", value: "created_at"
      value "SIZE", "Order CodeQL databases by size", value: "size"
    end
  end
end
