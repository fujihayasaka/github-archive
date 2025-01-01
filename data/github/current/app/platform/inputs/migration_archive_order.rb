# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MigrationArchiveOrder < Platform::Inputs::Base
      description "Ordering options for migration archives."

      argument :field, Enums::MigrationArchiveOrderField,
        "The field to order migration archives by.",
        required: true

      argument :direction, Enums::OrderDirection,
        "The ordering direction.",
        required: true
    end
  end
end
