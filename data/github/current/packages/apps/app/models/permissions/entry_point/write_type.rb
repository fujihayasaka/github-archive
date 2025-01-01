# typed: strict
# frozen_string_literal: true

module Permissions
  module EntryPoint
    class WriteType < T::Enum
      extend T::Sig

      enums do
        CREATE = new("insert_rows_requested")
        UPDATE = new("update_rows_requested")
        DELETE = new("deleted_rows")
      end
    end
  end
end
