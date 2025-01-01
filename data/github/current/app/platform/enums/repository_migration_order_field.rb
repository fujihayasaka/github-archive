# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryMigrationOrderField < Platform::Enums::Base
      description "Properties by which repository migrations can be ordered."

      value "CREATED_AT", "Order mannequins why when they were created.", value: :MIGRATION_ORDER_FIELD_CREATED_AT
    end
  end
end
