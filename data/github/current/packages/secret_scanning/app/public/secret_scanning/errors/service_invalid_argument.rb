# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Errors
    # Captures any :invalid_argument errors from TSS.
    class ServiceInvalidArgument < StandardError
    end
  end
end
