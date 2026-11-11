# typed: true
# frozen_string_literal: true

module GitHub
  # Public: Exception protocol that may be implemented to show a error message
  # directly to the user.
  module UIError
    # Public: Get error message string to show to user.
    #
    # Returns String.
    def ui_message
      "Looks like something went wrong!"
    end
  end
end
