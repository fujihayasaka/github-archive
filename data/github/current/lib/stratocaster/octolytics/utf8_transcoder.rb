# typed: true
# frozen_string_literal: true

require "github/encoding"

module Stratocaster
  module Octolytics
    class Utf8Transcoder
      attr_reader :transcoded_to_utf8

      def initialize(event)
        @event = event
      end

      # Recursively transcodes strings in the event structure to UTF-8.  Any
      # invalid characters will be replaced as the "replacement character"
      def transcode
        @transcoded_to_utf8 = false
        transcode_object(@event)
      end

      def transcode_object(object)
        case object
        when String
          object = object.dup if object.frozen?

          if object.force_encoding("UTF-8").valid_encoding?
            object
          else
            @transcoded_to_utf8 = true
            GitHub::Encoding.transcode(object, "UTF-8", "UTF-8")
          end
        when Hash
          Hash[object.map { |k, v| [k, transcode_object(v)] }]
        when Enumerable
          object.map { |v| transcode_object(v) }
        else
          object
        end
      end
    end
  end
end
