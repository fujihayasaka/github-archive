# frozen_string_literal: true

require "failbot"
require_relative "./exception_scrubber"

module Dependabot
  # Custom Failbot formatter that scrubs sensitive data from exception messages
  # and reports the original error class for wrapped updater errors.
  class FailbotFormatter < Failbot::ExceptionFormat::Structured
    def self.format_message(message)
      Dependabot::ExceptionScrubber.call(message)
    end

    def self.format_class_name(exception)
      if exception.respond_to?(:original_error_class)
        exception.original_error_class.to_s
      else
        exception.class.to_s
      end
    end
  end
end
