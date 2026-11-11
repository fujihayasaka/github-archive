# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class Stackframe < Platform::Inputs::Base
      description <<~MD
        A serialized Structured Stack Trace object.

        See https://github.com/github/failbotg/blob/master/docs/api.md#exception-detail
      MD

      visibility :internal

      argument :filename, String, "The file in the source where the exception occurred.", required: true
      argument :function, String, "Function or method that the exception occurred in.", required: true
      argument :lineno, String, "Line number in the filename.", required: true
      argument :colno, String, " Column number in the line provided in lineno.", required: false
    end
  end
end
