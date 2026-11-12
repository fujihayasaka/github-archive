# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Errors
    # Raised when an alert assignment targets a user who is not eligible to be
    # assigned in the given repository (no write access, or suspended).
    class InvalidAssignee < StandardError
    end
  end
end
