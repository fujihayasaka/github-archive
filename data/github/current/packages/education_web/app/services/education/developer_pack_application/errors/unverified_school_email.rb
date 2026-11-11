# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Errors
      class UnverifiedSchoolEmail < StandardError
        ERROR_MESSAGE = "The school email provided has not been verified. Please verify this email in your account settings."

        sig { returns(String) }
        def message
          ERROR_MESSAGE
        end
      end
    end
  end
end
