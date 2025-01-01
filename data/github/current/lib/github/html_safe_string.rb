# typed: false
# frozen_string_literal: true

# This module defines a helper method for defining frozen, html_safe Strings.
# This should be used to avoid linter warnings when making a constant string.
#
# Eg.
#   class MyController < ApplicationController
#     ERROR_MESSAGE = GitHub::HTMLSafeString.make("<blink>Something went wrong!</blink>")
#     def foo
#       render :html => ERROR_MESSAGE
#     end
#   end
module GitHub
  module HTMLSafeString
    def self.make(str)
      label = caller_locations(1, 1).first.base_label
      unless label.start_with?("<class", "<module")
        raise ArgumentError, "must be called from class or module definition."
      end

      str.html_safe.freeze # rubocop:disable Rails/OutputSafety
    end

    EMPTY        = make("")
    NBSP         = make("&nbsp;")
    BR           = make("<br>")
    DOUBLE_QUOTE = make('"')
    NEW_LINE     = make("\n")
  end
end
