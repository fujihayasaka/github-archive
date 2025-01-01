# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Errors
      class UserNotEligible < StandardError
        ERROR_MESSAGE = "User is not eligible to apply for the developer pack."

        sig { returns(String) }
        def message
          ERROR_MESSAGE
        end
      end
    end
  end
end
