# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Errors
    # Occurs when a write is attempted for a database entry but the
    # input row_version doesn't match the current database row_version.
    class RowVersionMismatch < StandardError
    end
  end
end
