# frozen_string_literal: true

require "rails-html-sanitizer"

module PresenterHelper
  # Sanitizes the given input string by removing any potentially dangerous HTML tags
  # while allowing a predefined list of safe HTML elements.
  #
  # Examples:
  #   "network_unsafe_http" -> "network_unsafe_http"  (remains unchanged)
  #
  #   "<p>This is a test</p>" -> "<p>This is a test</p>" (allowed HTML tag remains)
  #   "<script>alert('Hello')</script>" -> "" (HTML tags and potentially dangerous scripts are removed)
  #   "<a href='javascript:alert(\"XSS\")'>link</a>" -> "<a>link</a>" (dangerous attributes are removed)
  #
  # @param input [String, nil] the string to be sanitized
  # @return [String] the sanitized string with only safe HTML tags
  def sanitize_input(input)
    return "" if input.nil?

    sanitizer = Rails::Html::SafeListSanitizer.new
    sanitizer.sanitize(input)
  end
end
