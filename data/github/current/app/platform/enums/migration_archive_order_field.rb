# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MigrationArchiveOrderField < Platform::Enums::Base
      description "Properties by which migration archives can be ordered."

      value "CREATED_AT", "Order migration archives by when they were created.", value: "created_at"
    end
  end
end
