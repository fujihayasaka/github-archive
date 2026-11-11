# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryMigrationOrderDirection < Platform::Enums::Base
      description "Possible directions in which to order a list of repository migrations when provided an `orderBy` argument."

      value "ASC", "Specifies an ascending order for a given `orderBy` argument.", value: :MIGRATION_ORDER_DIRECTION_ASC
      value "DESC", "Specifies a descending order for a given `orderBy` argument.", value: :MIGRATION_ORDER_DIRECTION_DSC
    end
  end
end
