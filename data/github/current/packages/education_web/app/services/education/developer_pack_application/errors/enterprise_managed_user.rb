# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Errors
      class EnterpriseManagedUser < StandardError
        ERROR_MESSAGE = "Enterprise Managed Users are not eligible for the GitHub Student Developer Pack."

        sig { returns(String) }
        def message
          ERROR_MESSAGE
        end
      end
    end
  end
end
