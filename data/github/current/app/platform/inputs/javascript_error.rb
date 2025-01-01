# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class JavascriptError < Platform::Inputs::Base
      description <<~MD
        A serialized JavaScript Error object.

        Also see https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error.
      MD

      visibility :internal

      argument :type, String, "The error class name.", required: true
      argument :value, String, "The error message.", required: true
      argument :catalog_service, String, "The catalog service associated with the error.", required: false
      argument :stacktrace, [Inputs::Stackframe], "The structured stack from the error event.", required: true
    end
  end
end
