# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryMigrationOrder < Platform::Inputs::Base
      description "Ordering options for repository migrations."

      argument :field, Enums::RepositoryMigrationOrderField,
        "The field to order repository migrations by.",
        required: true

      argument :direction, Enums::RepositoryMigrationOrderDirection,
        "The ordering direction.",
        required: true
    end
  end
end
