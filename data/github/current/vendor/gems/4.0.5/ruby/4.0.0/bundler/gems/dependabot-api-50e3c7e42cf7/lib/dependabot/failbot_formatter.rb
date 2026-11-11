# frozen_string_literal: true

require "failbot"
require_relative "./exception_scrubber"

module Dependabot
  class FailbotFormatter < Failbot::ExceptionFormat::Structured
    # TODO: Patch the base class in Failbot to apply a noop filter that downstream implementations can filter?
    #
    # See: https://github.com/github/failbot/blob/950387988017ef60ec8071b8df4a5ea9f46c580e/lib/failbot/exception_format/structured.rb
    #
    # This reimplements the base class' method in order to apply 'Dependabot::ExceptionScrubber.call' to every
    # message passed to Failbot following the same handling of nested exceptions by looking at `e.cause`
    # Failbot::MAXIMUM_CAUSE_DEPTH times before truncating.
    #
    # rubocop:disable Style/RescueStandardError
    # rubocop:disable Naming/MethodParameterName
    # rubocop:disable Layout/LineLength
    # rubocop:disable Metrics/MethodLength
    def self.exception_details(e, frame_processing_pipeline)
      result = []
      depth = 0

      loop do
        message = e.message.to_s
        class_name = classname_from_exception(e)
        stacktrace = begin
          Failbot::BacktraceParser.call(e, frame_processing_pipeline: frame_processing_pipeline)
        rescue => e
          message += "\nUnable to parse backtrace (#{e.inspect})\nDon't put non-backtrace text in Exception#backtrace please!\nSo-called backtrace follows:\n#{e.backtrace.join("\n")}"
          class_name += " (backtrace failed to parse)"
          EMPTY_ARRAY
        end
        result.unshift({
                         "type" => class_name,
                         "value" => Dependabot::ExceptionScrubber.call(message),
                         "stacktrace" => stacktrace,
                       })
        depth += 1
        break unless (e = e.cause)

        if depth > Failbot::MAXIMUM_CAUSE_DEPTH
          result.unshift(FURTHER_CAUSES_WERE_OMITTED)
          break
        end
      end
      result
    end
    # rubocop:enable Style/RescueStandardError
    # rubocop:enable Naming/MethodParameterName
    # rubocop:enable Layout/LineLength
    # rubocop:enable Metrics/MethodLength

    def self.classname_from_exception(error)
      if error.respond_to?(:original_error_class)
        error.original_error_class.to_s
      else
        error.class.to_s
      end
    end
  end
end
