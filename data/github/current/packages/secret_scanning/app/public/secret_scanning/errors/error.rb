# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Errors
    # A generic error class for anything in Secret Scanning
    # that doesn't quite fit into a specific category.
    # This is to keep our stuff outside of the StandardError dumping zone.
    # Prefer a more specific error if possible, especially if it's high volume.
    class Error < StandardError
    end
  end
end
