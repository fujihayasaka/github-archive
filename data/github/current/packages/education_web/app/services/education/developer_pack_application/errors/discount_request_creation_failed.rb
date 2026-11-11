# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Errors
      class DiscountRequestCreationFailed < StandardError
        ERROR_MESSAGE = "There was an error creating the discount request. Errors: %{message}"

        sig { params(message: String).void }
        def initialize(message:)
          @message = message
        end

        sig { returns(String) }
        def message
          ERROR_MESSAGE % { message: @message }
        end
      end
    end
  end
end
