# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Cursor < Errors::Execution
      TYPE = "INVALID_CURSOR_ARGUMENTS"
      def initialize(cursor = nil)
        GitHub.dogstats.increment("platform.execute.error", tags: ["type:cursor"])
        phrase = cursor.nil? ? "The cursor" : "`#{cursor}`"
        message = "#{phrase} does not appear to be a valid cursor."
        super(TYPE, message)
      end
    end
  end
end
